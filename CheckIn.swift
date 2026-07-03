import CoreLocation
import Foundation

struct CheckIn: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let category: CheckInCategory
    var customLabel: String?
    let latitude: Double
    let longitude: Double
    let address: String
    var notes: String?
    var followUpCompleted: Bool
    var followUpResolvedAt: Date?
    var followUpStatus: CheckInFollowUpStatus?
    var tags: [EntryTag]

    var needsFollowUp: Bool {
        !followUpCompleted
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        category: CheckInCategory,
        customLabel: String? = nil,
        latitude: Double,
        longitude: Double,
        address: String = "",
        notes: String? = nil,
        followUpCompleted: Bool = false,
        followUpResolvedAt: Date? = nil,
        followUpStatus: CheckInFollowUpStatus? = nil,
        tags: [EntryTag] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.category = category
        self.customLabel = customLabel
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.notes = notes
        self.followUpCompleted = followUpCompleted
        self.followUpResolvedAt = followUpResolvedAt
        self.followUpStatus = followUpStatus
        self.tags = tags
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayLabel: String {
        if category == .other, let customLabel, !customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customLabel
        }

        return category.displayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case category
        case customLabel
        case latitude
        case longitude
        case address
        case notes
        case followUpCompleted
        case followUpResolvedAt
        case followUpStatus
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        category = try container.decode(CheckInCategory.self, forKey: .category)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        followUpCompleted = try container.decodeIfPresent(Bool.self, forKey: .followUpCompleted) ?? false
        followUpResolvedAt = try container.decodeIfPresent(Date.self, forKey: .followUpResolvedAt)
        followUpStatus = try container.decodeIfPresent(CheckInFollowUpStatus.self, forKey: .followUpStatus)
        tags = try container.decodeIfPresent([EntryTag].self, forKey: .tags) ?? []
    }
}

enum CheckInFollowUpStatus: String, Codable {
    case noIssues
    case noteAdded
    case incidentLogged
}

enum CheckInCategory: String, CaseIterable, Identifiable, Codable {
    case handoff
    case schoolPickupDropOff
    case doctorTherapy
    case mediation
    case courtAppearance
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .handoff:
            return "Handoff"
        case .schoolPickupDropOff:
            return "School pickup/drop-off"
        case .doctorTherapy:
            return "Doctor/therapy"
        case .mediation:
            return "Mediation"
        case .courtAppearance:
            return "Court appearance"
        case .other:
            return "Other"
        }
    }
}
