//  SyncManager.swift
//  MyNotes
//
//  iCloud sync (roadmap item 8): syncs pages, folders, and theme
//  across the user's devices through the CloudKit private database.
//
//  APPROACH — one CloudKit record, whole dataset as an asset:
//  The app's data is already one JSON blob per collection (pages,
//  folders, theme in UserDefaults). Sync keeps that shape: a single
//  CKRecord ("SyncData", record name "main") in the private database
//  holds the whole dataset as a CKAsset (a JSON file). The record's
//  server-side modification date is the last-write-wins clock.
//
//  Why not NSUbiquitousKeyValueStore: it caps at 1 MB total per app
//  (and 1 MB per key). Image blocks store downscaled JPEGs — a few
//  photos would blow that budget, and key-value storage has no
//  per-record conflict handling. CloudKit assets have no such
//  practical limit.
//
//  Why not one CKRecord per page: finer-grained conflicts, but far
//  more code (record-id mapping, per-record assets for images,
//  tombstones, partial-failure handling) for a single-user notes
//  app — and far more surface to get wrong without a compiler here.
//  A whole-dataset snapshot keeps the change small and the failure
//  modes simple: a failed sync never touches local data.
//
//  SAFETY RULES (local UserDefaults stays the source of truth —
//  iCloud is only a transport):
//  * If iCloud is unavailable (signed out, no container, no network)
//    the app works exactly as before, locally. Nothing is deleted
//    or overwritten because a sync failed.
//  * Uploads are debounced (2 s) so typing does not sync on every
//    keystroke; the local save to UserDefaults is still immediate.
//  * A remote snapshot is only applied when it is newer than the
//    last synced snapshot and the local copy has no unsynced change
//    — or when the remote copy is newer than the local change
//    (last-write-wins). A corrupt or unreadable remote snapshot is
//    ignored, never applied.
//  * Deletions sync naturally: the snapshot IS the dataset, so a
//    page missing from the remote snapshot was deleted on the other
//    device. Local Undo still works — undo restores the page locally
//    and the next debounced upload puts it back in iCloud.
//
//  SETUP (done by Christian in Xcode — not in this change): the
//  project has no iCloud capability yet. See the handoff report for
//  the exact steps (Signing & Capabilities → iCloud → CloudKit,
//  container iCloud.morrowchristian.MyNotes). Until that is enabled,
//  every CloudKit call fails with a missing-entitlement error, the
//  manager reports unavailable, and the app keeps working locally.
//
//  THREADING: this class is a plain ObservableObject (like
//  SidebarUndoCoordinator) and is only ever used from the main
//  thread. CloudKit's async calls run inside MainActor.run at the
//  Task entry points, so every mutation of published state and of
//  AppData happens on the main thread.

import CloudKit
import Combine
import CryptoKit
import Foundation
import UIKit

/// The whole local dataset, as one snapshot, for iCloud sync.
/// The record's server-side modification date is the timestamp —
/// the snapshot itself carries no clock, so there is only one
/// last-write-wins clock and it is set by CloudKit.
private struct SyncSnapshot: Codable {
    var pages: [Page]
    var folders: [Folder]
    var theme: AppTheme
}

/// The snapshot without anything else. Hashes are computed over this
/// only, so the same content always hashes the same.
private struct SyncContent: Codable {
    var pages: [Page]
    var folders: [Folder]
    var theme: AppTheme
}

final class CloudKitSyncManager: ObservableObject {
    // MARK: - Status (read by the Settings sheet)
    @Published private(set) var isAvailable = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?

    /// One-line status for the Settings sheet. Never claims a sync
    /// happened when it did not.
    var statusText: String {
        if !isAvailable {
            return "iCloud is not available — notes are stored on this device only."
        }
        if let error = lastError {
            return "Sync error: \(error)"
        }
        if isSyncing {
            return "Syncing…"
        }
        if let date = lastSyncDate {
            return "Last synced \(AppData.formatTimestamp(date))."
        }
        return "Sync is on — your notes have not synced yet."
    }

    // MARK: - Private state
    private weak var appData: AppData?
    private var cancellables = Set<AnyCancellable>()
    private var foregroundObserver: NSObjectProtocol?
    private var uploadWorkItem: DispatchWorkItem?
    private var uploadInFlight = false

    /// Set while a remote snapshot is being applied, so the
    /// publishers below do not treat the apply as a local edit
    /// (which would immediately upload the same data back). The
    /// hash check in noteLocalChange() is a second guard for the
    /// same case.
    private var isApplyingRemote = false

    /// Hash of the local content the last time a change was noted.
    /// Seeded at attach time so the initial publisher fire (which
    /// always delivers the current value) does not look like an edit.
    private var lastSeenLocalHash: String?

    // MARK: - CloudKit identity
    private let recordType = "SyncData"
    private let recordName = "main"
    private let container = CKContainer.default()
    private var database: CKDatabase { container.privateCloudDatabase }

    // Bookkeeping keys in UserDefaults (local only, never synced).
    // Persisted (not in-memory) so a conflict is still decided
    // correctly after an app restart.
    private let lastSyncedAtKey = "iCloudSyncLastSyncedAt"
    private let lastSyncedHashKey = "iCloudSyncLastSyncedHash"
    private let lastLocalChangeAtKey = "iCloudSyncLastLocalChangeAt"

    /// The server modification date of the snapshot the local data
    /// currently matches — either because we uploaded it or
    /// downloaded it.
    private var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncedAtKey) }
    }

    /// The content hash of that same snapshot.
    private var lastSyncedHash: String? {
        get { UserDefaults.standard.string(forKey: lastSyncedHashKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncedHashKey) }
    }

    /// When the local data last changed (nil when there is no
    /// unsynced local change). The local side of last-write-wins.
    private var lastLocalChangeAt: Date? {
        get { UserDefaults.standard.object(forKey: lastLocalChangeAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastLocalChangeAtKey) }
    }

    /// One encoder for sync payloads and hashes. sortedKeys makes the
    /// output deterministic (dictionary key order is otherwise
    /// unspecified), so the same content always hashes the same.
    private let syncEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: - Lifecycle
    /// Call once, from AppData.init after the local data is loaded.
    /// Seeds the change hash, subscribes to local changes, refreshes
    /// from iCloud when the app comes to the foreground, and does the
    /// first availability check + fetch.
    func attach(to appData: AppData) {
        self.appData = appData
        lastSeenLocalHash = currentContentHash()

        // Any local change (pages, folders, or theme) schedules a
        // debounced upload. Each sink fires immediately with the
        // current value, which the seeded hash above makes a no-op.
        appData.$pages.sink { [weak self] _ in self?.noteLocalChange() }
            .store(in: &cancellables)
        appData.$folders.sink { [weak self] _ in self?.noteLocalChange() }
            .store(in: &cancellables)
        appData.$theme.sink { [weak self] _ in self?.noteLocalChange() }
            .store(in: &cancellables)

        // Re-check iCloud whenever the app returns from the background.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncNow()
        }

        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { await self.checkAvailabilityAndFetch() }
        }
    }

    // MARK: - Local changes
    /// Called whenever pages, folders, or theme change. Ignores the
    /// assignments made while applying a remote snapshot, and ignores
    /// assignments that did not change the content (e.g. a save that
    /// re-assigns the same array). Anything else marks the local data
    /// changed and schedules a debounced upload.
    private func noteLocalChange() {
        guard !isApplyingRemote else { return }
        guard let hash = currentContentHash() else { return }
        guard hash != lastSeenLocalHash else { return }
        lastSeenLocalHash = hash
        lastLocalChangeAt = Date()
        scheduleUpload()
    }

    /// Debounce uploads by 2 seconds so typing does not sync on
    /// every keystroke. Each new change restarts the timer; the
    /// upload runs once the data has been quiet for 2 seconds.
    private func scheduleUpload() {
        uploadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.beginUpload()
        }
        uploadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func beginUpload() {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { await self.uploadIfNeeded() }
        }
    }

    // MARK: - Public entry points
    /// Manual sync (the "Sync Now" button in Settings). Fetches the
    /// remote snapshot and either applies it or uploads local data,
    /// whichever is newer. Safe to call any time; failures only set
    /// the status, they never touch local data.
    func syncNow() {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { await self.fetchRemoteAndDecide() }
        }
    }

    // MARK: - Availability + fetch
    private func checkAvailabilityAndFetch() async {
        await refreshAvailability()
        guard isAvailable else { return }
        await fetchRemoteAndDecide()
    }

    /// Re-checks whether this device can reach its private CloudKit
    /// database. Until the iCloud capability is enabled in Xcode this
    /// returns .couldNotDetermine (missing entitlement) and sync stays
    /// off — the app keeps working locally.
    private func refreshAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
            if status != .available {
                lastError = nil
            }
        } catch {
            isAvailable = false
        }
    }

    // MARK: - Upload
    /// Uploads the current local dataset if it differs from the last
    /// synced snapshot. Called after the debounce, on first sync, and
    /// when the fetch step decides the local copy is newer.
    private func uploadIfNeeded() async {
        guard !uploadInFlight else { return }
        guard let appData else { return }
        guard let contentHash = currentContentHash(), contentHash != lastSyncedHash else { return }
        guard isAvailable else {
            // Availability may have changed since launch (e.g. the
            // user just signed into iCloud) — check once, then retry
            // on the next change or foreground.
            await refreshAvailability()
            return
        }

        uploadInFlight = true
        isSyncing = true
        defer {
            uploadInFlight = false
            isSyncing = false
        }

        let snapshot = SyncSnapshot(
            pages: appData.pages,
            folders: appData.folders,
            theme: appData.theme
        )
        do {
            guard let payload = try? syncEncoder.encode(snapshot) else { return }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mynotes-sync-\(UUID().uuidString).json")
            try payload.write(to: fileURL)
            // The asset reads the file during the save; remove it after.
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let record: CKRecord
            do {
                record = try await database.fetch(withRecordID: CKRecord.ID(recordName: recordName))
            } catch let error as CKError where error.code == .unknownItem {
                // First sync — no record exists yet.
                record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName))
            }

            record["data"] = CKAsset(fileURL: fileURL)
            let savedRecord: CKRecord
            do {
                savedRecord = try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Another device uploaded between our fetch and save.
                // Release the in-flight guard so the decide step below
                // can upload again if the local copy is still newer.
                uploadInFlight = false
                isSyncing = false
                await fetchRemoteAndDecide()
                return
            }

            // The server's modification date is the timestamp the
            // next conflict is decided against.
            lastSyncedAt = savedRecord.modificationDate ?? Date()
            lastSyncedHash = contentHash
            lastSeenLocalHash = contentHash
            lastLocalChangeAt = nil
            lastSyncDate = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Download
    /// Fetches the remote snapshot and decides what to do:
    /// * No record yet → first sync: upload the local data.
    /// * Remote unchanged since last sync → nothing to do (or upload
    ///   if the local copy changed).
    /// * Remote newer, local unchanged → apply the remote snapshot.
    /// * Both changed → last-write-wins by timestamp (remote
    ///   server modification date vs local last-change date).
    /// A missing, corrupt, or unreadable remote snapshot never
    /// touches local data.
    private func fetchRemoteAndDecide() async {
        guard appData != nil else { return }
        guard isAvailable else {
            await refreshAvailability()
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let record = try await database.fetch(withRecordID: CKRecord.ID(recordName: recordName))
            let remoteModifiedAt = record.modificationDate ?? Date.distantPast
            guard let asset = record["data"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let payload = try? Data(contentsOf: fileURL),
                  let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: payload),
                  let remoteHash = contentHash(of: snapshot) else {
                // Record exists but is unreadable — never touch local data.
                lastError = "The iCloud copy could not be read; keeping the notes on this device."
                return
            }

            // Remote matches what we last synced — upload instead if
            // the local copy changed since.
            if remoteHash == lastSyncedHash {
                if currentContentHash() != lastSyncedHash {
                    await uploadIfNeeded()
                } else {
                    lastSyncedAt = remoteModifiedAt
                    lastSyncDate = Date()
                }
                return
            }

            let localChanged = currentContentHash() != lastSyncedHash
            if !localChanged {
                applyRemote(snapshot, remoteModifiedAt: remoteModifiedAt, hash: remoteHash)
                return
            }

            // Both sides changed since the last sync: last write wins.
            // (Local time is the device clock, remote time is the
            // CloudKit server clock — a device clock that is far off
            // can tip a close call the wrong way.)
            if let localAt = lastLocalChangeAt, localAt > remoteModifiedAt {
                await uploadIfNeeded()
            } else {
                applyRemote(snapshot, remoteModifiedAt: remoteModifiedAt, hash: remoteHash)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Nothing in iCloud yet — push the local data up.
            await uploadIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Apply
    /// Replaces the local dataset with a remote snapshot. The local
    /// UserDefaults copy is rewritten by the assignments' didSet
    /// hooks, so the app still works offline afterwards. Folder page
    /// ids are deduped with the same rule as loadFolders.
    private func applyRemote(_ snapshot: SyncSnapshot, remoteModifiedAt: Date, hash: String) {
        guard let appData else { return }
        isApplyingRemote = true
        var folders = snapshot.folders
        var seen: Set<UUID> = []
        for i in folders.indices {
            folders[i].pageIDs.removeAll { id in
                if seen.contains(id) { return true }
                seen.insert(id)
                return false
            }
        }
        appData.pages = snapshot.pages
        appData.folders = folders
        appData.theme = snapshot.theme
        isApplyingRemote = false
        lastSyncedAt = remoteModifiedAt
        lastSyncedHash = hash
        lastSeenLocalHash = hash
        lastLocalChangeAt = nil
        lastSyncDate = Date()
        lastError = nil
    }

    // MARK: - Hashing
    /// Hash of the current local content (pages + folders + theme),
    /// or nil if it cannot be encoded.
    private func currentContentHash() -> String? {
        guard let appData else { return nil }
        let content = SyncContent(pages: appData.pages, folders: appData.folders, theme: appData.theme)
        guard let data = try? syncEncoder.encode(content) else { return nil }
        return sha256Hex(data)
    }

    /// Hash of a decoded remote snapshot's content, or nil if it
    /// cannot be encoded (treated as unreadable by the caller).
    private func contentHash(of snapshot: SyncSnapshot) -> String? {
        let content = SyncContent(pages: snapshot.pages, folders: snapshot.folders, theme: snapshot.theme)
        guard let data = try? syncEncoder.encode(content) else { return nil }
        return sha256Hex(data)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
