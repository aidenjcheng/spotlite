import Foundation
import Observation

@Observable
final class TrackSaveStatus {
    let trackID: String
    var isSaved: Bool

    init(trackID: String, isSaved: Bool) {
        self.trackID = trackID
        self.isSaved = isSaved
    }
}
