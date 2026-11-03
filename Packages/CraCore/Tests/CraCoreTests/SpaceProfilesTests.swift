import CraCore
import Foundation
import Testing

/// A new space starts on the profile of the space it is made from, as in Arc.
struct SpaceProfilesTests {
    private func space(profile: UUID?) -> Space {
        Space(id: UUID(), title: "S", emoji: "🌱", theme: SpaceTheme.presets[0], favoritesContainerID: UUID(),
              pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: Date(), profileID: profile)
    }

    @Test func newSpaceTakesTheFocusedSpacesProfile() {
        let work = BrowserProfile(id: UUID(), name: "Work")
        #expect(SpaceProfiles.forNewSpace(from: space(profile: work.id), profiles: [work]) == work.id)
        #expect(SpaceProfiles.forNewSpace(from: space(profile: nil), profiles: [work]) == nil, "Default stays Default")
        #expect(SpaceProfiles.forNewSpace(from: nil, profiles: [work]) == nil)
    }

    @Test func aMissingProfileIsDefault() {
        #expect(SpaceProfiles.forNewSpace(from: space(profile: UUID()), profiles: []) == nil)
    }
}
