//
// Created by Krzysztof Zablocki on 11/09/2016.
// Copyright (c) 2016 Pixle. All rights reserved.
//

import Foundation

/// Defines Swift type
class Type: NSObject, SourceryModel, Annotated {

    // All local typealiases
    // sourcery: skipJSExport
    var typealiases: [String: Typealias] {
        didSet {
            typealiases.values.forEach { $0.parent = self }
        }
    }

    // sourcery: skipJSExport
    internal var isExtension: Bool

    /// Kind of type declaration, i.e. `enum`, `struct`, `class`, `protocol` or `extension`
    // sourcery: forceEquality
    var kind: String { return isExtension ? "extension" : "unknown" }

    /// Type access level, i.e. `internal`, `private`, `fileprivate`, `public`, `open`
    let accessLevel: String

    /// Type name in global scope. For inner types includes the name of its containing type, i.e. `Type.Inner`
    var name: String {
        guard let parentName = parent?.name else { return localName }
        return "\(parentName).\(localName)"
    }

    /// Whether type is generic
    var isGeneric: Bool

    /// Name in its own scope.
    var localName: String

    /// Variables defined in this type only, inluding variables defined in extensions, 
    /// but excluding those from superclasses (for classes only) and protocols
    var variables: [Variable]

    /// All variables defined for this type, including variables defined in extensions,
    /// in superclasses (for classes only) and protocols
    // sourcery: skipEquality, skipDescription
    var allVariables: [Variable] {
        return flattenAll({
            return $0.variables
            //return ($0 is Protocol) ? [] : $0.variables
        }, filter: { all, extracted in
            !all.contains(where: { $0.name == extracted.name && $0.isStatic == extracted.isStatic })
        })
    }

    /// Methods defined in this type only, inluding methods defined in extensions,
    /// but excluding those from superclasses (for classes only) and protocols
    var methods: [Method]

    /// All methods defined for this type, including methods defined in extensions,
    /// in superclasses (for classes only) and protocols
    // sourcery: skipEquality, skipDescription
    var allMethods: [Method] {
        return flattenAll({ $0.methods })
    }

    private func flattenAll<T>(_ extraction: @escaping (Type) -> [T], filter: (([T], T) -> Bool)? = nil) -> [T] {
        let all = NSMutableOrderedSet()
        all.addObjects(from: extraction(self))

        let filteredExtraction = { (target: Type) -> [T] in
            if let filter = filter {
                // swiftlint:disable:next force_cast
                let all = all.array as! [T]
                let extracted = extraction(target).filter({ filter(all, $0) })
                return extracted
            } else {
                return extraction(target)
            }
        }

        inherits.values.forEach { all.addObjects(from: filteredExtraction($0)) }
        implements.values.forEach { all.addObjects(from: filteredExtraction($0)) }

        return all.array.flatMap { $0 as? T }
    }

    /// All initializers defined in this type
    var initializers: [Method] {
        return methods.filter { $0.isInitializer }
    }

    /// Type annotations, grouped by name
    var annotations: [String: NSObject] = [:]

    /// Static variables defined in this type
    var staticVariables: [Variable] {
        return variables.filter { $0.isStatic }
    }

    /// Instance variables defined in this type
    var instanceVariables: [Variable] {
        return variables.filter { !$0.isStatic }
    }

    /// Computed instance variables defined in this type
    var computedVariables: [Variable] {
        return variables.filter { $0.isComputed && !$0.isStatic }
    }

    /// Stored instance variables defined in this type
    var storedVariables: [Variable] {
        return variables.filter { !$0.isComputed && !$0.isStatic }
    }

    /// Names of types this type inherits from (for classes only) and protocols it implements, in order of definition
    var inheritedTypes: [String] {
        didSet {
            based.removeAll()
            inheritedTypes.forEach { name in
                self.based[name] = name
            }
        }
    }

    /// Names of types or protocols this type inherits from, including unknown (not scanned) types
    // sourcery: skipEquality, skipDescription
    var based = [String: String]()

    /// Types this type inherits from (only for classes)
    // sourcery: skipEquality, skipDescription
    var inherits = [String: Type]()

    /// Protocols this type implements
    // sourcery: skipEquality, skipDescription
    var implements = [String: Type]()

    /// Contained types
    var containedTypes: [Type] {
        didSet {
            containedTypes.forEach { $0.parent = self }
        }
    }

    /// Name of parent type (for container types only)
    private(set) var parentName: String?

    /// Parent type, if known (for container types only)
    // sourcery: skipEquality, skipDescription
    var parent: Type? {
        didSet {
            parentName = parent?.name
        }
    }

    // sourcery: skipJSExport
    var parentTypes: AnyIterator<Type> {
        var next: Type? = self
        return AnyIterator {
            next = next?.parent
            return next
        }
    }

    // Superclass type, if known (only for classes)
    // sourcery: skipEquality, skipDescription
    var supertype: Type?

    /// Type attributes, i.e. `@objc`
    var attributes: [String: Attribute]

    // Underlying parser data, never to be used by anything else
    // sourcery: skipDescription, skipEquality, skipCoding, skipJSExport
    internal var __parserData: Any?

    init(name: String = "",
         parent: Type? = nil,
         accessLevel: AccessLevel = .internal,
         isExtension: Bool = false,
         variables: [Variable] = [],
         methods: [Method] = [],
         inheritedTypes: [String] = [],
         containedTypes: [Type] = [],
         typealiases: [Typealias] = [],
         attributes: [String: Attribute] = [:],
         annotations: [String: NSObject] = [:],
         isGeneric: Bool = false) {

        let name = name.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        self.localName = name
        self.accessLevel = accessLevel.rawValue
        self.isExtension = isExtension
        self.variables = variables
        self.methods = methods
        self.inheritedTypes = inheritedTypes
        self.containedTypes = containedTypes
        self.typealiases = [:]
        self.parent = parent
        self.parentName = parent?.name
        self.attributes = attributes
        self.annotations = annotations
        self.isGeneric = isGeneric

        super.init()
        containedTypes.forEach { $0.parent = self }
        inheritedTypes.forEach { name in
            self.based[name] = name
        }
        typealiases.forEach({
            $0.parent = self
            self.typealiases[$0.aliasName] = $0
        })
    }

    func extend(_ type: Type) {
        self.variables += type.variables
        self.methods += type.methods
        self.inheritedTypes += type.inheritedTypes

        type.annotations.forEach { self.annotations[$0.key] = $0.value }
        type.inherits.forEach { self.inherits[$0.key] = $0.value }
        type.implements.forEach { self.implements[$0.key] = $0.value }
    }

    // sourcery:inline:Type.AutoCoding
        required init?(coder aDecoder: NSCoder) {
            guard let typealiases: [String: Typealias] = aDecoder.decode(forKey: "typealiases") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["typealiases"])); fatalError() }; self.typealiases = typealiases
            self.isExtension = aDecoder.decode(forKey: "isExtension")
            guard let accessLevel: String = aDecoder.decode(forKey: "accessLevel") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["accessLevel"])); fatalError() }; self.accessLevel = accessLevel
            self.isGeneric = aDecoder.decode(forKey: "isGeneric")
            guard let localName: String = aDecoder.decode(forKey: "localName") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["localName"])); fatalError() }; self.localName = localName
            guard let variables: [Variable] = aDecoder.decode(forKey: "variables") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["variables"])); fatalError() }; self.variables = variables
            guard let methods: [Method] = aDecoder.decode(forKey: "methods") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["methods"])); fatalError() }; self.methods = methods
            guard let annotations: [String: NSObject] = aDecoder.decode(forKey: "annotations") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["annotations"])); fatalError() }; self.annotations = annotations
            guard let inheritedTypes: [String] = aDecoder.decode(forKey: "inheritedTypes") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["inheritedTypes"])); fatalError() }; self.inheritedTypes = inheritedTypes
            guard let based: [String: String] = aDecoder.decode(forKey: "based") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["based"])); fatalError() }; self.based = based
            guard let inherits: [String: Type] = aDecoder.decode(forKey: "inherits") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["inherits"])); fatalError() }; self.inherits = inherits
            guard let implements: [String: Type] = aDecoder.decode(forKey: "implements") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["implements"])); fatalError() }; self.implements = implements
            guard let containedTypes: [Type] = aDecoder.decode(forKey: "containedTypes") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["containedTypes"])); fatalError() }; self.containedTypes = containedTypes
            self.parentName = aDecoder.decode(forKey: "parentName")
            self.parent = aDecoder.decode(forKey: "parent")
            self.supertype = aDecoder.decode(forKey: "supertype")
            guard let attributes: [String: Attribute] = aDecoder.decode(forKey: "attributes") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["attributes"])); fatalError() }; self.attributes = attributes
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(self.typealiases, forKey: "typealiases")
            aCoder.encode(self.isExtension, forKey: "isExtension")
            aCoder.encode(self.accessLevel, forKey: "accessLevel")
            aCoder.encode(self.isGeneric, forKey: "isGeneric")
            aCoder.encode(self.localName, forKey: "localName")
            aCoder.encode(self.variables, forKey: "variables")
            aCoder.encode(self.methods, forKey: "methods")
            aCoder.encode(self.annotations, forKey: "annotations")
            aCoder.encode(self.inheritedTypes, forKey: "inheritedTypes")
            aCoder.encode(self.based, forKey: "based")
            aCoder.encode(self.inherits, forKey: "inherits")
            aCoder.encode(self.implements, forKey: "implements")
            aCoder.encode(self.containedTypes, forKey: "containedTypes")
            aCoder.encode(self.parentName, forKey: "parentName")
            aCoder.encode(self.parent, forKey: "parent")
            aCoder.encode(self.supertype, forKey: "supertype")
            aCoder.encode(self.attributes, forKey: "attributes")
        }
    // sourcery:end
}

extension Type {

    // sourcery: skipDescription, skipJSExport
    var isClass: Bool {
        let isNotClass = self is Struct || self is Enum || self is Protocol
        return !isNotClass && !isExtension
    }
}
