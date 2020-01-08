/**
*  Publish
*  Copyright (c) John Sundell 2019
*  MIT license, see LICENSE file for details
*/

import XCTest
import Publish
import Files

final class PodcastFeedGenerationTests: PublishTestCase {
    func testOnlyIncludingSpecifiedSection() throws {
        let folder = try Folder.createTemporary()

        try generateFeed(in: folder, content: [
            "one/a.md": """
            \(makeStubbedAudioMetadata())
            # Included
            """,
            "two/b": "# Not included"
        ])

        let intermediateFolder = try folder.subfolder(at: ".intermediate")
        let feed = try intermediateFolder.file(at: "Output/feed.rss").readAsString()
        XCTAssertTrue(feed.contains("Included"))
        XCTAssertFalse(feed.contains("Not included"))
    }

    func testConvertingRelativeLinksToAbsolute() throws {
        let folder = try Folder.createTemporary()

        try generateFeed(in: folder, content: [
            "one/item.md": """
            \(makeStubbedAudioMetadata())
            BEGIN [Link](/page) ![Image](/image.png) [Link](https://apple.com) END
            """
        ])

        let intermediateFolder = try folder.subfolder(at: ".intermediate")
        let feed = try intermediateFolder.file(at: "Output/feed.rss").readAsString()
        let substring = feed.substrings(between: "BEGIN ", and: " END").first

        XCTAssertEqual(substring, """
        <a href="https://swiftbysundell.com/page">Link</a> \
        <img src=\"https://swiftbysundell.com/image.png\" alt=\"Image\"/> \
        <a href="https://apple.com">Link</a>
        """)
    }

    func testReusingPreviousFeedIfNoItemsWereModified() throws {
        let folder = try Folder.createTemporary()
        let contentFile = try folder.createFile(at: "Content/one/item.md")
        try contentFile.write(makeStubbedAudioMetadata())

        try generateFeed(in: folder)
        let intermediateFolder = try folder.subfolder(at: ".intermediate")
        let feedA = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        let newDate = Date().addingTimeInterval(60 * 60)
        try generateFeed(in: folder, date: newDate)
        let feedB = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        XCTAssertEqual(feedA, feedB)

        try contentFile.append("New content")
        try generateFeed(in: folder, date: newDate)
        let feedC = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        XCTAssertNotEqual(feedB, feedC)
    }

    func testNotReusingPreviousFeedIfConfigChanged() throws {
        let folder = try Folder.createTemporary()
        let contentFile = try folder.createFile(at: "Content/one/item.md")
        try contentFile.write(makeStubbedAudioMetadata())

        try generateFeed(in: folder)
        let intermediateFolder = try folder.subfolder(at: ".intermediate")
        let feedA = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        var newConfig = try makeConfigStub()
        newConfig.author.name = "New author name"
        let newDate = Date().addingTimeInterval(60 * 60)
        try generateFeed(in: folder, config: newConfig, date: newDate)
        let feedB = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        XCTAssertNotEqual(feedA, feedB)
    }

    func testNotReusingPreviousFeedIfItemWasAdded() throws {
        let folder = try Folder.createTemporary()

        let audio = try Audio(
            url: require(URL(string: "https://audio.mp3")),
            duration: Audio.Duration(),
            byteSize: 55
        )

        let itemA = Item<Site>(
            path: "a",
            sectionID: .one,
            metadata: .init(podcast: .init()),
            content: Content(audio: audio)
        )

        let itemB = Item<Site>(
            path: "b",
            sectionID: .one,
            metadata: .init(podcast: .init()),
            content: Content(
                lastModified: itemA.lastModified,
                audio: audio
            )
        )

        try generateFeed(in: folder, generationSteps: [
            .addItem(itemA)
        ])

        let intermediateFolder = try folder.subfolder(at: ".intermediate")
        let feedA = try intermediateFolder.file(at: "Output/feed.rss").readAsString()

        try generateFeed(in: folder, generationSteps: [
            .addItem(itemA),
            .addItem(itemB)
        ])

        let feedB = try intermediateFolder.file(at: "Output/feed.rss").readAsString()
        XCTAssertNotEqual(feedA, feedB)
    }
}

extension PodcastFeedGenerationTests {
    static var allTests: Linux.TestList<PodcastFeedGenerationTests> {
        [
            ("testOnlyIncludingSpecifiedSection", testOnlyIncludingSpecifiedSection),
            ("testConvertingRelativeLinksToAbsolute", testConvertingRelativeLinksToAbsolute),
            ("testReusingPreviousFeedIfNoItemsWereModified", testReusingPreviousFeedIfNoItemsWereModified),
            ("testNotReusingPreviousFeedIfConfigChanged", testNotReusingPreviousFeedIfConfigChanged),
            ("testNotReusingPreviousFeedIfItemWasAdded", testNotReusingPreviousFeedIfItemWasAdded)
        ]
    }
}

private extension PodcastFeedGenerationTests {
    typealias Site = WebsiteStub.WithPodcastMetadata
    typealias Configuration = PodcastFeedConfiguration<Site>

    func makeConfigStub() throws -> Configuration {
        try Configuration(
            targetPath: .defaultForRSSFeed,
            imageURL: require(URL(string: "image.png")),
            copyrightText: "John Appleseed 2019",
            author: PodcastAuthor(
                name: "John Appleseed",
                emailAddress: "john.appleseed@apple.com"
            ),
            description: "Description",
            subtitle: "Subtitle",
            category: "Category"
        )
    }

    func makeStubbedAudioMetadata() -> String {
        """
        ---
        audio.url: https://audio.mp3
        audio.duration: 05:02
        audio.size: 12345
        ---
        """
    }

    func generateFeed(
        in folder: Folder,
        config: Configuration? = nil,
        generationSteps: [PublishingStep<Site>] = [
            .copyContentAndResourceFilesToIntermediateFolder(),
            .addMarkdownFiles()
        ],
        date: Date = Date(),
        content: [Path : String] = [:]
    ) throws {
        try publishWebsiteWithPodcast(in: folder, using: [
            .group(generationSteps),
            .generatePodcastFeed(
                for: .one,
                config: config ?? makeConfigStub(),
                date: date
            )
        ], content: content)
    }
}
