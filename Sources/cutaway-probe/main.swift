import Foundation

// cutaway-probe: connects to a CutawayServer and checks every frame it sends.
// It covers the handshake, the first app state event, the app icon, the layer hierarchy and
// the screenshots and attributes of every layer. The flow is in Probe.swift, the checks in the
// *Checks.swift files, and those for the demo app in Demo/.

exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
