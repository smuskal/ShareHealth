import Foundation

extension Notification.Name {
    static let handleIncomingURL = Notification.Name("handleIncomingURL")
    static let receivedHourSteps = Notification.Name("receivedHourSteps")
    static let refreshStepsData = Notification.Name("refreshStepsData")
    static let changeDate = Notification.Name("changeDate")
    
    // Group notifications by purpose
    struct StepData {
        static let updated = Notification.Name("stepDataUpdated")
        static let failed = Notification.Name("stepDataFailed")
        static let zeroed = Notification.Name("stepDataZeroed")
    }
    
    struct Import {
        static let started = Notification.Name("importStarted")
        static let completed = Notification.Name("importCompleted")
        static let failed = Notification.Name("importFailed")
    }
    
    struct UI {
        static let dateChanged = Notification.Name("uiDateChanged")
        static let timeRangeChanged = Notification.Name("uiTimeRangeChanged")
    }
}
