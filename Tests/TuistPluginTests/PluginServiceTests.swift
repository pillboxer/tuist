import MockableTest
import Path
import struct ProjectDescription.Plugin
import struct ProjectDescription.PluginLocation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistScaffold
import TuistScaffoldTesting
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistPlugin

final class PluginServiceTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoading!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    private var gitHandler: MockGitHandler!
    private var subject: PluginService!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactoring!
    private var fileUnarchiver: MockFileUnarchiving!
    private var fileClient: MockFileClient!

    override func setUp() {
        super.setUp()
        manifestLoader = .init()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        gitHandler = MockGitHandler()
        let mockCacheDirectoriesProvider = MockCacheDirectoriesProviding()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider
        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(try! temporaryPath())
        cacheDirectoryProviderFactory = .init()
        given(cacheDirectoryProviderFactory)
            .cacheDirectories()
            .willReturn(cacheDirectoriesProvider)
        fileUnarchiver = MockFileUnarchiving()
        let fileArchivingFactory = MockFileArchivingFactorying()

        given(fileArchivingFactory).makeFileUnarchiver(for: .any).willReturn(fileUnarchiver)

        fileClient = MockFileClient()
        subject = PluginService(
            manifestLoader: manifestLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            fileHandler: fileHandler,
            gitHandler: gitHandler,
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            fileArchivingFactory: fileArchivingFactory,
            fileClient: fileClient
        )
    }

    override func tearDown() {
        manifestLoader = nil
        templatesDirectoryLocator = nil
        gitHandler = nil
        cacheDirectoriesProvider = nil
        cacheDirectoryProviderFactory = nil
        fileUnarchiver = nil
        fileClient = nil
        subject = nil
        super.tearDown()
    }

    func test_remotePluginPaths() throws {
        // Given
        let pluginAGitURL = "https://url/to/repo/a.git"
        let pluginAGitSha = "abc"
        let pluginAFingerprint = "\(pluginAGitURL)-\(pluginAGitSha)".md5
        let pluginBGitURL = "https://url/to/repo/b.git"
        let pluginBGitTag = "abc"
        let pluginBFingerprint = "\(pluginBGitURL)-\(pluginBGitTag)".md5
        let pluginCGitURL = "https://url/to/repo/c.git"
        let pluginCGitTag = "abc"
        let pluginCFingerprint = "\(pluginCGitURL)-\(pluginCGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginAGitURL, gitReference: .sha(pluginAGitSha), directory: nil, releaseUrl: nil),
                .git(url: pluginBGitURL, gitReference: .tag(pluginBGitTag), directory: nil, releaseUrl: nil),
                .git(url: pluginCGitURL, gitReference: .tag(pluginCGitTag), directory: "Sub/Subfolder", releaseUrl: nil),
            ]
        )
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())
        let pluginADirectory = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginAFingerprint)
        let pluginBDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginBFingerprint)
        let pluginCDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginCFingerprint)
        try fileHandler.touch(
            pluginBDirectory.appending(components: PluginServiceConstants.release)
        )

        // When
        let remotePluginPaths = try subject.remotePluginPaths(using: config)

        // Then
        XCTAssertEqual(
            Set(remotePluginPaths),
            Set([
                RemotePluginPaths(
                    repositoryPath: pluginADirectory.appending(component: PluginServiceConstants.repository),
                    releasePath: nil
                ),
                RemotePluginPaths(
                    repositoryPath: pluginBDirectory.appending(component: PluginServiceConstants.repository),
                    releasePath: pluginBDirectory.appending(component: PluginServiceConstants.release)
                ),
                RemotePluginPaths(
                    repositoryPath: pluginCDirectory.appending(component: PluginServiceConstants.repository)
                        .appending(component: "Sub").appending(component: "Subfolder"),
                    releasePath: nil
                ),
            ])
        )
    }

    func test_fetchRemotePlugins_when_git_sha() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitSha = "abc"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitSha)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .sha(pluginGitSha), directory: nil, releaseUrl: nil),
            ]
        )
        var invokedCloneURL: String?
        var invokedClonePath: Path.AbsolutePath?
        gitHandler.cloneToStub = { url, path in
            invokedCloneURL = url
            invokedClonePath = path
        }
        var invokedCheckoutID: String?
        var invokedCheckoutPath: Path.AbsolutePath?
        gitHandler.checkoutStub = { id, path in
            invokedCheckoutID = id
            invokedCheckoutPath = path
        }
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())

        // When
        _ = try await subject.fetchRemotePlugins(using: config)

        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitSha)
        XCTAssertEqual(
            invokedCheckoutPath,
            try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }

    func test_fetchRemotePlugins_when_git_tag_and_repository_not_cached() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .tag(pluginGitTag), directory: nil, releaseUrl: nil),
            ]
        )
        var invokedCloneURL: String?
        var invokedClonePath: Path.AbsolutePath?
        gitHandler.cloneToStub = { url, path in
            invokedCloneURL = url
            invokedClonePath = path
        }
        var invokedCheckoutID: String?
        var invokedCheckoutPath: Path.AbsolutePath?
        gitHandler.checkoutStub = { id, path in
            invokedCheckoutID = id
            invokedCheckoutPath = path
        }
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())

        // When
        _ = try await subject.fetchRemotePlugins(using: config)

        // Then
        XCTAssertEqual(invokedCloneURL, pluginGitURL)
        XCTAssertEqual(
            invokedClonePath,
            try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
        XCTAssertEqual(invokedCheckoutID, pluginGitTag)
        XCTAssertEqual(
            invokedCheckoutPath,
            try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
                .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        )
    }

    func test_fetchRemotePlugins_when_git_tag_and_repository_cached() async throws {
        // Given
        let pluginGitURL = "https://url/to/repo.git"
        let pluginGitTag = "1.0.0"
        let pluginFingerprint = "\(pluginGitURL)-\(pluginGitTag)".md5
        let config = mockConfig(
            plugins: [
                .git(url: pluginGitURL, gitReference: .tag(pluginGitTag), directory: nil, releaseUrl: nil),
            ]
        )

        let temporaryDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(temporaryDirectory)

        let pluginDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(component: pluginFingerprint)
        try fileHandler.touch(
            pluginDirectory
                .appending(components: PluginServiceConstants.repository, Constants.SwiftPackageManager.packageSwiftName)
        )
        let commandPath = pluginDirectory.appending(components: PluginServiceConstants.release, "tuist-command")
        try fileHandler.touch(commandPath)

        // When / Then
        _ = try await subject.fetchRemotePlugins(using: config)
    }

    func test_loadPlugins_WHEN_localHelpers() async throws {
        // Given
        let pluginPath = try temporaryPath().appending(component: "Plugin")
        let pluginName = "TestPlugin"

        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
            )

        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        let config = mockConfig(plugins: [TuistCore.PluginLocation.local(path: pluginPath.pathString)])

        try fileHandler.createFolder(
            pluginPath.appending(component: Constants.helpersDirectoryName)
        )

        // When
        let plugins = try await subject.loadPlugins(using: config)

        // Then
        let expectedHelpersPath = pluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins
            .test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .local)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitHelpers() async throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())

        let cachedPluginPath = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"

        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
            )

        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        try fileHandler.createFolder(cachedPluginPath.appending(component: Constants.helpersDirectoryName))

        let config = mockConfig(plugins: [
            TuistCore.PluginLocation.git(
                url: pluginGitUrl,
                gitReference: .tag(pluginGitReference),
                directory: nil,
                releaseUrl: nil
            ),
        ])
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())

        // When
        let plugins = try await subject.loadPlugins(using: config)

        // Then
        let expectedHelpersPath = cachedPluginPath.appending(component: Constants.helpersDirectoryName)
        let expectedPlugins = Plugins
            .test(projectDescriptionHelpers: [.init(name: pluginName, path: expectedHelpersPath, location: .remote)])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_when_localResourceSynthesizer() async throws {
        // Given
        let pluginPath = try temporaryPath()
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = pluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(.init(validating: resourceTemplatesPath.pathString))

        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
            )

        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        let config = mockConfig(plugins: [TuistCore.PluginLocation.local(path: pluginPath.pathString)])

        // When
        let plugins = try await subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            resourceSynthesizers: [
                PluginResourceSynthesizer(name: pluginName, path: resourceTemplatesPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_when_remoteResourceSynthesizer() async throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())
        let cachedPluginPath = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let resourceTemplatesPath = cachedPluginPath.appending(components: "ResourceSynthesizers")

        try makeDirectories(.init(validating: resourceTemplatesPath.pathString))

        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
            )
        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        let config =
            mockConfig(plugins: [
                TuistCore.PluginLocation.git(
                    url: pluginGitUrl,
                    gitReference: .tag(pluginGitReference),
                    directory: nil,
                    releaseUrl: nil
                ),
            ])

        // When
        let plugins = try await subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(
            resourceSynthesizers: [
                PluginResourceSynthesizer(name: pluginName, path: resourceTemplatesPath),
            ]
        )
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_localTemplate() async throws {
        // Given
        let pluginPath = try temporaryPath()
        let pluginName = "TestPlugin"
        let templatePath = pluginPath.appending(components: "Templates", "custom")
        templatesDirectoryLocator.templatePluginDirectoriesStub = { _ in
            [
                templatePath,
            ]
        }

        try makeDirectories(.init(validating: templatePath.pathString))

        // When
        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [.local(path: .relativeToRoot(pluginPath.pathString))])
            )
        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        let config = mockConfig(plugins: [TuistCore.PluginLocation.local(path: pluginPath.pathString)])

        // Then
        let plugins = try await subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    func test_loadPlugins_WHEN_gitTemplate() async throws {
        // Given
        let pluginGitUrl = "https://url/to/repo.git"
        let pluginGitReference = "1.0.0"
        let pluginFingerprint = "\(pluginGitUrl)-\(pluginGitReference)".md5
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try temporaryPath())
        let cachedPluginPath = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
            .appending(components: pluginFingerprint, PluginServiceConstants.repository)
        let pluginName = "TestPlugin"
        let templatePath = cachedPluginPath.appending(components: "Templates", "custom")
        templatesDirectoryLocator.templatePluginDirectoriesStub = { _ in
            [
                templatePath,
            ]
        }

        try makeDirectories(.init(validating: templatePath.pathString))

        // When
        given(manifestLoader)
            .loadConfig(at: .any)
            .willReturn(
                .test(plugins: [ProjectDescription.PluginLocation.git(url: pluginGitUrl, tag: pluginGitReference)])
            )

        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(
                ProjectDescription.Plugin(name: pluginName)
            )

        let config =
            mockConfig(plugins: [
                TuistCore.PluginLocation
                    .git(url: pluginGitUrl, gitReference: .tag(pluginGitReference), directory: nil, releaseUrl: nil),
            ])

        // Then
        let plugins = try await subject.loadPlugins(using: config)
        let expectedPlugins = Plugins.test(templatePaths: [templatePath])
        XCTAssertEqual(plugins, expectedPlugins)
    }

    private func mockConfig(plugins: [TuistCore.PluginLocation]) -> TuistCore.Config {
        TuistCore.Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            swiftVersion: nil,
            plugins: plugins,
            generationOptions: .test(),
            path: nil
        )
    }
}
