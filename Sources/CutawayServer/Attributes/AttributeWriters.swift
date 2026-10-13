#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Why a value cannot be written, completing a sentence that begins with the attribute's ID:
/// "cannot be negative". Sent as the message of an `InvalidAttributeValue` error
/// (PROTOCOL.md, P-SET-03).
struct AttributeRejection: Error, Equatable {
    let reason: String

    init(_ reason: String) {
        self.reason = reason
    }

    /// A value of another member than the attribute's. `AttributeEditing` refuses those before
    /// a writer sees them.
    static let otherKind = Self("takes another kind of value")
}

/// Turns a value from the wire into a change of one attribute of `Subject`.
///
/// `prepare` only checks and converts; the closure it returns makes the change, so nothing
/// changes before every check has passed (P-SET-03). `AttributeEditing` has already checked
/// the member, nil, non-finite numbers and the attribute's limits (P-SET-07): a writer sees a
/// value of its attribute's kind within its limits, and `nil` only where the attribute
/// accepts it.
struct AttributeWriter<Subject> {
    let prepare: (Subject, AttributeValue?) -> Result<() -> Void, AttributeRejection>
}

extension AttributeWriter where Subject: UIView {
    /// A content hugging or compression resistance priority, set with `set`.
    static func priority(_ set: @escaping (Subject, UILayoutPriority) -> Void) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.number(value).map { number in
                { set(subject, UILayoutPriority(Float(number))) }
            }
        }
    }
}

extension AttributeWriter where Subject: AnyObject {
    static func bool(_ keyPath: ReferenceWritableKeyPath<Subject, Bool>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .bool(let flag)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = flag }
        }
    }

    static func int(_ keyPath: ReferenceWritableKeyPath<Subject, Int>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .int(let number)? = value, let int = Int(exactly: number) else {
                return .failure(.otherKind)
            }
            return .success { subject[keyPath: keyPath] = int }
        }
    }

    static func number(_ keyPath: ReferenceWritableKeyPath<Subject, CGFloat>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.number(value).map { number in { subject[keyPath: keyPath] = CGFloat(number) } }
        }
    }

    static func number(_ keyPath: ReferenceWritableKeyPath<Subject, Float>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.number(value).map { number in { subject[keyPath: keyPath] = Float(number) } }
        }
    }

    static func point(_ keyPath: ReferenceWritableKeyPath<Subject, CGPoint>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .point(let point)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = CGPoint(point) }
        }
    }

    static func size(_ keyPath: ReferenceWritableKeyPath<Subject, CGSize>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .size(let size)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = CGSize(size) }
        }
    }

    static func rect(_ keyPath: ReferenceWritableKeyPath<Subject, CGRect>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .rect(let rect)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = CGRect(rect) }
        }
    }

    static func insets(_ keyPath: ReferenceWritableKeyPath<Subject, UIEdgeInsets>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .insets(let insets)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = UIEdgeInsets(insets) }
        }
    }

    static func transform(_ keyPath: ReferenceWritableKeyPath<Subject, CATransform3D>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .transform(let transform)? = value else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = CATransform3D(transform) }
        }
    }

    /// `nil` writes nil.
    static func cgColor(_ keyPath: ReferenceWritableKeyPath<Subject, CGColor?>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.color(value).map { color in { subject[keyPath: keyPath] = color } }
        }
    }

    /// `nil` writes nil: UIKit's own default, for the properties that have one.
    static func uiColor(_ keyPath: ReferenceWritableKeyPath<Subject, UIColor?>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.color(value)
                .map { color in { subject[keyPath: keyPath] = color.map(UIColor.init(cgColor:)) } }
        }
    }

    /// `nil` writes nil.
    static func string(_ keyPath: ReferenceWritableKeyPath<Subject, String?>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.string(value).map { text in { subject[keyPath: keyPath] = text } }
        }
    }

    /// A UIKit enumeration, by its raw value. `AttributeEditing` has checked that the value is
    /// one of the cases (P-SET-02).
    static func enumeration<Case: RawRepresentable>(
        _ keyPath: ReferenceWritableKeyPath<Subject, Case>
    ) -> AttributeWriter where Case.RawValue == Int {
        AttributeWriter { subject, value in
            guard case .enumeration(let raw, _, _, _)? = value, let int = Int(exactly: raw),
                  let newCase = Case(rawValue: int)
            else { return .failure(.otherKind) }
            return .success { subject[keyPath: keyPath] = newCase }
        }
    }

    /// The font of that name at the current size; the system's size when there is no font.
    ///
    /// `UIFont(name:size:)` gives another font for some names instead of nil: for the system
    /// font's own name (".SFUI-Regular") it gives Times New Roman. So the current font and the
    /// system font are matched by name first, and any other font must have the name asked for.
    static func fontName(_ keyPath: ReferenceWritableKeyPath<Subject, UIFont?>) -> AttributeWriter {
        AttributeWriter { subject, value in
            guard case .string(let name)? = value else { return .failure(.otherKind) }
            let current = subject[keyPath: keyPath]
            let size = current?.pointSize ?? UIFont.systemFontSize
            let font: UIFont
            if let current, current.fontName == name {
                font = current
            } else if UIFont.systemFont(ofSize: size).fontName == name {
                font = UIFont.systemFont(ofSize: size)
            } else if let named = UIFont(name: name, size: size), named.fontName == name {
                font = named
            } else {
                return .failure(AttributeRejection("cannot be \"\(name)\": no font has that name"))
            }
            return .success { subject[keyPath: keyPath] = font }
        }
    }

    /// The current font at that size; the system font when there is no font.
    static func fontSize(_ keyPath: ReferenceWritableKeyPath<Subject, UIFont?>) -> AttributeWriter {
        AttributeWriter { subject, value in
            AttributeInputs.number(value).map { number in
                let size = CGFloat(number)
                let font = subject[keyPath: keyPath]?.withSize(size) ?? UIFont.systemFont(ofSize: size)
                return { subject[keyPath: keyPath] = font }
            }
        }
    }
}
#endif
