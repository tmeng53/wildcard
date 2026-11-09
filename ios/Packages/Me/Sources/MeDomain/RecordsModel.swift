import Observation

/// Where 外卡记录 is while it reads the member's records.
public enum RecordsLoad: Hashable, Sendable {
    case loading
    case loaded(WildcardRecords)
    case failed(MeError)
}

/// 外卡记录 on screen: the member's records, read each time the page opens.
@MainActor @Observable
public final class RecordsModel {
    public private(set) var load: RecordsLoad = .loading
    @ObservationIgnored private let service: any MeService

    public init(service: any MeService) {
        self.service = service
    }

    /// Reads the records; a try after a failure shows the loader again. Keeps what is on screen
    /// when a refresh fails.
    public func reload() async {
        if case .failed = load { load = .loading }
        do {
            load = .loaded(try await service.records())
        } catch {
            guard !Task.isCancelled else { return }
            if case .loaded = load { return }
            load = .failed(error)
        }
    }
}
