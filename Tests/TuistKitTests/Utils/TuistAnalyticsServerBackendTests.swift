import FileSystem
import Mockable
import ServiceContextModule
import TuistAnalytics
import TuistCore
import TuistCoreTesting
import TuistServer
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistAnalyticsServerBackendTests: TuistUnitTestCase {
    private var fullHandle = "tuist-org/tuist"
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var ciChecker: MockCIChecking!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!
    private var subject: TuistAnalyticsServerBackend!

    override func setUpWithError() throws {
        super.setUp()
        createCommandEventService = .init()
        ciChecker = .init()
        cacheDirectoriesProvider = .init()
        analyticsArtifactUploadService = .init()
        cacheDirectoriesProvider = .init()
        subject = TuistAnalyticsServerBackend(
            fullHandle: fullHandle,
            url: Constants.URLs.production,
            createCommandEventService: createCommandEventService,
            fileHandler: fileHandler,
            ciChecker: ciChecker,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: FileSystem()
        )
    }

    override func tearDown() {
        createCommandEventService = nil
        ciChecker = nil
        cacheDirectoriesProvider = nil
        analyticsArtifactUploadService = nil
        subject = nil
        super.tearDown()
    }

    func test_send_when_is_not_ci() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try temporaryPath())
            given(ciChecker)
                .isCI()
                .willReturn(false)
            let event = CommandEvent.test()
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(
                    .test(
                        id: 10,
                        url: URL(string: "https://tuist.dev/tuist-org/tuist/runs/10")!
                    )
                )

            // When
            try await subject.send(commandEvent: event)

            // Then
            XCTAssertPrinterOutputNotContains("You can view a detailed report at: https://tuist.dev/tuist-org/tuist/runs/10")
        }
    }

    func test_send_when_is_ci() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try temporaryPath())
            given(ciChecker)
                .isCI()
                .willReturn(true)
            let event = CommandEvent.test()
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(
                    .test(
                        id: 10,
                        url: URL(string: "https://tuist.dev/tuist-org/tuist/runs/10")!
                    )
                )

            // When
            try await subject.send(commandEvent: event)

            // Then
            XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://tuist.dev/tuist-org/tuist/runs/10")
        }
    }

    func test_send_when_is_ci_and_result_bundle_exists() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            given(ciChecker)
                .isCI()
                .willReturn(true)
            let event = CommandEvent.test()
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(
                    .test(
                        id: 10,
                        url: URL(string: "https://tuist.dev/tuist-org/tuist/runs/10")!
                    )
                )

            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try temporaryPath())

            let resultBundle = try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: event.runId, "\(Constants.resultBundleName).xcresult")
            try fileHandler.createFolder(resultBundle)

            given(analyticsArtifactUploadService)
                .uploadResultBundle(
                    .value(resultBundle),
                    targetHashes: .any,
                    graphPath: .any,
                    commandEventId: .value(10),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(())

            // When
            try await subject.send(commandEvent: event)

            // Then
            XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://tuist.dev/tuist-org/tuist/runs/10")
            let exists = try await fileSystem.exists(resultBundle)
            XCTAssertFalse(exists)
        }
    }
}
