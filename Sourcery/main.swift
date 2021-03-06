//
//  main.swift
//  Sourcery
//
//  Created by Krzysztof Zablocki on 09/12/2016.
//  Copyright © 2016 Pixle. All rights reserved.
//

import Foundation
import Commander
import PathKit
import Yams

extension Path: ArgumentConvertible {
    public init(parser: ArgumentParser) throws {
        if let path = parser.shift() {
            self.init(path)
        } else {
            throw ArgumentError.missingValue(argument: nil)
        }
    }
}

struct CustomArguments: ArgumentConvertible {
    let arguments: Annotations

    init(parser: ArgumentParser) throws {
        guard let args = try parser.shiftValueForOption("args") else {
            self.arguments = Annotations()
            return
        }

        self.arguments = AnnotationsParser.parse(line: args)
    }

    init(arguments: [String: NSObject] = [:]) {
        self.arguments = arguments
    }

    var description: String {
        return arguments.description
    }

}

fileprivate enum Validators {
    static func isReadable(path: Path) -> Path {
        if !path.isReadable {
            print("'\(path)' does not exist or is not readable.")
            exit(1)
        }

        return path
    }

    static func isFileOrDirectory(path: Path) -> Path {
        _ = isReadable(path: path)

        if !(path.isDirectory || path.isFile) {
            print("'\(path)' isn't a directory or proper file.")
            exit(2)
        }

        return path
    }
}

struct Configuration {

    let sources: [Path]
    let templates: [Path]
    let output: Path
    let args: [String: NSObject]

    init(dict: [String: Any]) {
        let sources = (dict["sources"] as? [String])?.map({ Path($0) }) ?? []
        let templates = (dict["templates"] as? [String])?.map({ Path($0) }) ?? []
        let output = (dict["output"] as? String).map({ Path($0) }) ?? "."
        let args = dict["args"] as? [String: NSObject] ?? [:]

        self.init(sources: sources, templates: templates, output: output, args: args)
    }

    init(sources: [Path], templates: [Path], output: Path, args: [String: NSObject]) {
        self.sources = sources
        self.templates = templates
        self.output = output
        self.args = args
    }

    func validate() {
        _ = sources.map(Validators.isFileOrDirectory(path:))
        _ = templates.map(Validators.isFileOrDirectory(path:))
        _ = Validators.isFileOrDirectory(path:output)
    }

}

func runCLI() {
    command(
        Flag("watch",
             flag: "w",
             description: "Watch template for changes and regenerate as needed."),
        Flag("disableCache",
             flag: "w",
             description: "Stops using cache."),
        Flag("verbose",
             flag: "v",
             description: "Turn on verbose logging for ignored entities"),
        VariadicOption<Path>("sources", description: "Path to a source swift files"),
        VariadicOption<Path>("templates", description: "Path to templates. File or Directory."),
        Option<Path>("output", ".", description: "Path to output. Directory. Default is current path."),
        Argument<CustomArguments>("args", description: "Custom values to pass to templates.")
    ) { watcherEnabled, disableCache, verboseLogging, sources, templates, output, args in
        do {
            let configuration: Configuration

            let yamlPath: Path = ".sourcery.yml"
            if let yaml = try? Yams.Node(string: yamlPath.read()).flatten(), let dict = yaml as? [String: Any] {
                configuration = Configuration(dict: dict)
            } else {
                configuration = Configuration(sources: sources,
                                              templates: templates,
                                              output: output,
                                              args: args.arguments)
            }

            configuration.validate()

            let start = CFAbsoluteTimeGetCurrent()
            if let keepAlive = try Sourcery(verbose: verboseLogging, watcherEnabled: watcherEnabled, cacheDisabled: disableCache, arguments: configuration.args).processFiles(configuration.sources, usingTemplates: configuration.templates, output: configuration.output) {
                RunLoop.current.run()
                _ = keepAlive
            } else {
                print("Processing time \(CFAbsoluteTimeGetCurrent() - start) seconds")
            }
        } catch {
            print(error)
            exit(4)
        }
        }.run(Sourcery.version)
}

public var inUnitTests = NSClassFromString("XCTest") != nil

#if os(macOS)
import AppKit

if !inUnitTests {
    runCLI()
} else {
    //! Need to run something for tests to work
    final class TestApplicationController: NSObject, NSApplicationDelegate {
        let window =   NSWindow()

        func applicationDidFinishLaunching(aNotification: NSNotification) {
            window.setFrame(CGRect(x: 0, y: 0, width: 0, height: 0), display: false)
            window.makeKeyAndOrderFront(self)
        }

        func applicationWillTerminate(aNotification: NSNotification) {
        }

    }

    autoreleasepool { () -> Void in
        let app =   NSApplication.shared()
        let controller =   TestApplicationController()

        app.delegate   = controller
        app.run()
    }
}
#endif
