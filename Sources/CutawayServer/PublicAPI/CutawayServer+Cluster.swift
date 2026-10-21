// Compiled in every configuration; see CutawayServer+Description.swift.
#if canImport(UIKit)
// The clusters and slots of Cutaway's protocol, as its table lists them: `cluster: .font.size`.
// Each cluster is a value whose properties are its slots.

extension CutawayServer.Attribute.Cluster {
    /// Whether an object shows, and how much.
    public static let visibility = VisibilitySlots()
    /// Rounded corners and clipping to them.
    public static let corners = CornersSlots()
    /// A border.
    public static let border = BorderSlots()
    /// A shadow.
    public static let shadow = ShadowSlots()
    /// Where an object is and how it is placed.
    public static let geometry = GeometrySlots()
    /// How Auto Layout sizes an object.
    public static let sizing = SizingSlots()
    /// How an object takes part in Auto Layout.
    public static let autoLayout = AutoLayoutSlots()
    /// A font.
    public static let font = FontSlots()
    /// The lines of a text.
    public static let lines = LinesSlots()
    /// The state of a control.
    public static let state = StateSlots()
    /// Scrolling.
    public static let scrolling = ScrollingSlots()
    /// An image: its name or symbol name, size, scale, rendering mode and symbol configuration.
    public static let image = ImageSlots()
    /// Where a cell is in its list; for a table, `item` is the row.
    public static let indexPath = IndexPathSlots()
    /// The sections of a list, and its items in all sections together.
    public static let listCounts = ListCountsSlots()

    /// The slots of `visibility`.
    public struct VisibilitySlots: Sendable {
        /// Hidden or not, as `UIView.isHidden`.
        public let hidden = Self.slot("hidden")
        /// As `UIView.alpha`.
        public let opacity = Self.slot("opacity")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("visibility", slot: slot)
        }
    }

    /// The slots of `corners`.
    public struct CornersSlots: Sendable {
        /// As `CALayer.cornerRadius`.
        public let radius = Self.slot("radius")
        /// Clipping, as `UIView.clipsToBounds`.
        public let clip = Self.slot("clip")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("corners", slot: slot)
        }
    }

    /// The slots of `border`.
    public struct BorderSlots: Sendable {
        /// As `CALayer.borderWidth`.
        public let width = Self.slot("width")
        /// As `CALayer.borderColor`.
        public let color = Self.slot("color")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("border", slot: slot)
        }
    }

    /// The slots of `shadow`.
    public struct ShadowSlots: Sendable {
        /// As `CALayer.shadowColor`.
        public let color = Self.slot("color")
        /// As `CALayer.shadowOpacity`.
        public let opacity = Self.slot("opacity")
        /// As `CALayer.shadowRadius`.
        public let radius = Self.slot("radius")
        /// As `CALayer.shadowOffset`.
        public let offset = Self.slot("offset")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("shadow", slot: slot)
        }
    }

    /// The slots of `geometry`.
    public struct GeometrySlots: Sendable {
        /// As `CALayer.frame`.
        public let frame = Self.slot("frame")
        /// As `CALayer.bounds`.
        public let bounds = Self.slot("bounds")
        /// As `CALayer.position`.
        public let position = Self.slot("position")
        /// As `CALayer.anchorPoint`.
        public let anchor = Self.slot("anchor")
        /// As `CALayer.zPosition`.
        public let zPosition = Self.slot("zPosition")
        /// As `CALayer.transform`.
        public let transform = Self.slot("transform")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("geometry", slot: slot)
        }
    }

    /// The slots of `sizing`.
    public struct SizingSlots: Sendable {
        /// The horizontal content hugging priority.
        public let huggingHorizontal = Self.slot("hugging.horizontal")
        /// The vertical content hugging priority.
        public let huggingVertical = Self.slot("hugging.vertical")
        /// The horizontal compression resistance priority.
        public let compressionHorizontal = Self.slot("compression.horizontal")
        /// The vertical compression resistance priority.
        public let compressionVertical = Self.slot("compression.vertical")
        /// The width of the intrinsic content size.
        public let intrinsicWidth = Self.slot("intrinsic.width")
        /// The height of the intrinsic content size.
        public let intrinsicHeight = Self.slot("intrinsic.height")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("sizing", slot: slot)
        }
    }

    /// The slots of `autoLayout`.
    public struct AutoLayoutSlots: Sendable {
        /// As `UIView.translatesAutoresizingMaskIntoConstraints`.
        public let autoresizing = Self.slot("autoresizing")
        /// As `UIView.hasAmbiguousLayout`.
        public let ambiguous = Self.slot("ambiguous")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("autoLayout", slot: slot)
        }
    }

    /// The slots of `font`.
    public struct FontSlots: Sendable {
        /// The font's name.
        public let name = Self.slot("name")
        /// The font's size.
        public let size = Self.slot("size")
        /// The text style the font was made for.
        public let textStyle = Self.slot("textStyle")
        /// Whether the font follows the text size, as `adjustsFontForContentSizeCategory`.
        public let scalable = Self.slot("scalable")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("font", slot: slot)
        }
    }

    /// The slots of `lines`.
    public struct LinesSlots: Sendable {
        /// The most lines, as `UILabel.numberOfLines`.
        public let count = Self.slot("count")
        /// How lines break, as `UILabel.lineBreakMode`.
        public let lineBreak = Self.slot("lineBreak")
        /// The lines actually drawn.
        public let drawn = Self.slot("drawn")
        /// Whether the text is truncated.
        public let truncated = Self.slot("truncated")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("lines", slot: slot)
        }
    }

    /// The slots of `state`.
    public struct StateSlots: Sendable {
        /// As `UIControl.isEnabled`.
        public let enabled = Self.slot("enabled")
        /// As `UIControl.isSelected`.
        public let selected = Self.slot("selected")
        /// As `UIControl.isHighlighted`.
        public let highlighted = Self.slot("highlighted")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("state", slot: slot)
        }
    }

    /// The slots of `scrolling`.
    public struct ScrollingSlots: Sendable {
        /// As `UIScrollView.isScrollEnabled`.
        public let enabled = Self.slot("enabled")
        /// As `UIScrollView.isPagingEnabled`.
        public let paging = Self.slot("paging")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("scrolling", slot: slot)
        }
    }

    /// The slots of `image`.
    public struct ImageSlots: Sendable {
        /// The image's name, or its symbol's name.
        public let name = Self.slot("name")
        /// The image's size.
        public let size = Self.slot("size")
        /// The image's scale.
        public let scale = Self.slot("scale")
        /// The image's rendering mode.
        public let renderingMode = Self.slot("renderingMode")
        /// The symbol image's configuration.
        public let symbolConfiguration = Self.slot("symbolConfiguration")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("image", slot: slot)
        }
    }

    /// The slots of `indexPath`.
    public struct IndexPathSlots: Sendable {
        /// The section.
        public let section = Self.slot("section")
        /// The item; for a table, the row.
        public let item = Self.slot("item")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("indexPath", slot: slot)
        }
    }

    /// The slots of `listCounts`.
    public struct ListCountsSlots: Sendable {
        /// The number of sections.
        public let sections = Self.slot("sections")
        /// The number of items in all sections together.
        public let items = Self.slot("items")

        private static func slot(_ slot: String) -> CutawayServer.Attribute.Cluster {
            .init("listCounts", slot: slot)
        }
    }
}
#endif
