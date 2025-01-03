import FileSystem
import Foundation
import Mockable
import ServiceContextModule
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoader
@testable import TuistSupportTesting

final class DumpServiceTests: TuistTestCase {
    private var subject: DumpService!
    private var fileSystem: FileSysteming!

    override func setUp() {
        super.setUp()
        fileSystem = FileSystem()
        subject = DumpService()
    }

    override func tearDown() {
        fileSystem = nil
        subject = nil
        super.tearDown()
    }

    func test_prints_the_manifest_when_project_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            import ProjectDescription

            let project = Project(
                name: "tuist",
                organizationName: "tuist",
                settings: nil,
                targets: [],
                resourceSynthesizers: []
            )
            """
            try config.write(
                toFile: tmpDir.appending(component: "Project.swift").pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .project)
            let expectedStart = """
            {
              "additionalFiles": [

              ],
              "name": "tuist",
              "options": {
                "automaticSchemesOptions": {
                  "enabled": {
                    "codeCoverageEnabled": false,
                    "targetSchemesGrouping": {
                      "byNameSuffix": {
                        "build": [
            """
            // middle part is ignored as order of suffixes is not predictable
            let expectedEnd = """
                        ]
                      }
                    },
                    "testingOptions": 0
                  }
                },
                "disableBundleAccessors": false,
                "disableShowEnvironmentVarsInScriptPhases": false,
                "disableSynthesizedResourceAccessors": false,
                "textSettings": {

                }
              },
              "organizationName": "tuist",
              "packages": [

              ],
              "resourceSynthesizers": [

              ],
              "schemes": [

              ],
              "targets": [

              ]
            }

            """

            XCTAssertPrinterOutputContains(expectedStart)
            XCTAssertPrinterOutputContains(expectedEnd)
        }
    }

    func test_prints_the_manifest_when_workspace_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            import ProjectDescription

            let workspace = Workspace(
                name: "tuist",
                projects: [],
                schemes: [],
                fileHeaderTemplate: nil,
                additionalFiles: []
            )
            """
            try config.write(
                toFile: tmpDir.appending(component: "Workspace.swift").pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .workspace)
            let expected = """
            {
              "additionalFiles": [

              ],
              "generationOptions": {
                "autogeneratedWorkspaceSchemes": {
                  "enabled": {
                    "codeCoverageMode": {
                      "disabled": {

                      }
                    },
                    "testingOptions": 0
                  }
                },
                "enableAutomaticXcodeSchemes": false,
                "renderMarkdownReadme": false
              },
              "name": "tuist",
              "projects": [

              ],
              "schemes": [

              ]
            }

            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_prints_the_manifest_when_config_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            import ProjectDescription

            let config = Config(
                compatibleXcodeVersions: .all,
                fullHandle: "tuist/tuist",
                swiftVersion: nil,
                plugins: [],
                generationOptions: .options(),
                installOptions: .options(
                    passthroughSwiftPackageManagerArguments: [
                        "--replace-scm-with-registry"
                    ]
                )
            )
            """
            try config.write(
                toFile: tmpDir.appending(components: "Tuist.swift").pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .config)
            let expected = """
            {
              "fullHandle": "tuist/tuist",
              "project": {
                "tuist": {
                  "compatibleXcodeVersions": {
                    "all": {

                    }
                  },
                  "generationOptions": {
                    "disablePackageVersionLocking": false,
                    "enforceExplicitDependencies": false,
                    "optionalAuthentication": false,
                    "resolveDependenciesWithSystemScm": false,
                    "staticSideEffectsWarningTargets": {
                      "all": {

                      }
                    }
                  },
                  "installOptions": {
                    "passthroughSwiftPackageManagerArguments": [
                      "--replace-scm-with-registry"
                    ]
                  },
                  "plugins": [

                  ]
                }
              },
              "url": "https://tuist.dev"
            }
            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_prints_the_manifest_when_template_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            import ProjectDescription

            let template = Template(
                description: "tuist",
                attributes: [],
                items: []
            )
            """
            try config.write(
                toFile: tmpDir.appending(component: "\(tmpDir.basenameWithoutExt).swift").pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .template)
            let expected = """
            {
              "attributes": [

              ],
              "description": "tuist",
              "items": [

              ]
            }

            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_prints_the_manifest_when_plugin_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            import ProjectDescription

            let plugin = Plugin(
                name: "tuist"
            )
            """
            try config.write(
                toFile: tmpDir.appending(component: "Plugin.swift").pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .plugin)
            let expected = """
            {
              "name": "tuist"
            }

            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_prints_the_manifest_when_package_manifest() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            // swift-tools-version: 5.9
            import PackageDescription

            #if TUIST
            import ProjectDescription

            let packageSettings = PackageSettings(
                targetSettings: ["TargetA": ["OTHER_LDFLAGS": "-ObjC"]]
            )

            #endif

            let package = Package(
                name: "PackageName",
                dependencies: []
            )

            """
            try fileHandler.createFolder(tmpDir.appending(component: Constants.tuistDirectoryName))
            try config.write(
                toFile: tmpDir.appending(
                    component: Constants.SwiftPackageManager.packageSwiftName
                ).pathString,
                atomically: true,
                encoding: .utf8
            )
            try await subject.run(path: tmpDir.pathString, manifest: .package)
            let expected = """
            {
              "baseSettings": {
                "base": {

                },
                "configurations": [
                  {
                    "name": {
                      "rawValue": "Debug"
                    },
                    "settings": {

                    },
                    "variant": "debug"
                  },
                  {
                    "name": {
                      "rawValue": "Release"
                    },
                    "settings": {

                    },
                    "variant": "release"
                  }
                ],
                "defaultSettings": {
                  "recommended": {
                    "excluding": [

                    ]
                  }
                }
              },
            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_prints_the_manifest_when_package_manifest_without_package_settings() async throws {
        try await ServiceContext.withTestingDependencies {
            let tmpDir = try temporaryPath()
            let config = """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "PackageName",
                dependencies: []
            )

            """
            try await fileSystem.makeDirectory(at: tmpDir.appending(component: Constants.tuistDirectoryName))
            try await fileSystem.writeText(
                config,
                at: tmpDir.appending(
                    component: Constants.SwiftPackageManager.packageSwiftName
                )
            )
            try await subject.run(path: tmpDir.pathString, manifest: .package)
            let expected = """
            {
              "baseSettings": {
                "base": {

                },
                "configurations": [
                  {
                    "name": {
                      "rawValue": "Debug"
                    },
                    "settings": {

                    },
                    "variant": "debug"
                  },
                  {
                    "name": {
                      "rawValue": "Release"
                    },
                    "settings": {

                    },
                    "variant": "release"
                  }
                ],
                "defaultSettings": {
                  "recommended": {
                    "excluding": [

                    ]
                  }
                }
              },
            """

            XCTAssertPrinterOutputContains(expected)
        }
    }

    func test_run_throws_when_project_and_file_doesnt_exist() async throws {
        try await assertLoadingRaisesWhenManifestNotFound(manifest: .project)
    }

    func test_run_throws_when_workspace_and_file_doesnt_exist() async throws {
        try await assertLoadingRaisesWhenManifestNotFound(manifest: .workspace)
    }

    func test_run_throws_when_config_and_file_doesnt_exist() async throws {
        try await assertLoadingRaisesWhenManifestNotFound(manifest: .config)
    }

    func test_run_throws_when_template_and_file_doesnt_exist() async throws {
        try await assertLoadingRaisesWhenManifestNotFound(manifest: .template)
    }

    func test_run_throws_when_plugin_and_file_doesnt_exist() async throws {
        try await assertLoadingRaisesWhenManifestNotFound(manifest: .plugin)
    }

    func test_run_throws_when_the_manifest_loading_fails() async throws {
        for manifest in DumpableManifest.allCases {
            let tmpDir = try temporaryPath()
            try "invalid config".write(
                toFile: tmpDir.appending(component: manifest.manifest.fileName(tmpDir)).pathString,
                atomically: true,
                encoding: .utf8
            )
            do {
                try await subject.run(path: tmpDir.pathString, manifest: manifest)
                XCTFail("Expected error not thrown")
            } catch {
                // can't use XCTAssertError because it doesn't support async
            }
        }
    }

    // MARK: - Helpers

    private func assertLoadingRaisesWhenManifestNotFound(manifest: DumpableManifest) async throws {
        try await fileHandler.inTemporaryDirectory { tmpDir in
            var expectedDirectory = tmpDir
            if manifest == .config {
                if try await !self.fileSystem.exists(expectedDirectory) {
                    try await self.fileSystem.makeDirectory(at: expectedDirectory)
                }
            }
            await self.XCTAssertThrowsSpecific(
                try await self.subject.run(path: tmpDir.pathString, manifest: manifest),
                ManifestLoaderError.manifestNotFound(manifest.manifest, expectedDirectory)
            )
        }
    }
}

extension DumpableManifest {
    var manifest: Manifest {
        switch self {
        case .project:
            return .project
        case .workspace:
            return .workspace
        case .config:
            return .config
        case .template:
            return .template
        case .plugin:
            return .plugin
        case .package:
            return .packageSettings
        }
    }
}
