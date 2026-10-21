import Foundation

// cutaway-probe: connects to a CutawayServer and checks every frame it sends.
// It covers the handshake, the first app state event, the app icon, the layer hierarchy, the
// screenshots, attributes and constraints of every layer, and the environment. With
// `--expect-demo` it also checks what the demo app shows, and changes it and changes it back:
// a subtree and an attribute on the main screen, a constraint's outcome, an override of the
// environment on the Lists page, and the host app's extensions on the Extensions page.
// The flow is in Probe.swift, the checks in Checks/, and those for the demo app in Demo/, with
// the steps that change it in Demo/DemoFlow.swift and Demo/ExtensionsChecks.swift.

exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
