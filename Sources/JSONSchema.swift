//
//  JSONSchema.swift
//  JSONSchema
//
//  Created by Kyle Fuller on 07/03/2015.
//  Copyright (c) 2015 Cocode. All rights reserved.
//

import Foundation

public enum Type: String {
  case object  = "object"
  case array   = "array"
  case string  = "string"
  case integer = "integer"
  case number  = "number"
  case boolean = "boolean"
  case null    = "null"
}

extension String {
  func removePrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let index = characters.index(startIndex, offsetBy: prefix.characters.count)
    return substring(from: index)
  }
}

public enum SchemaKey: String {
  case title = "title"
  case description = "description"
  case type = "type"
  case reference = "$ref"
  case allOf = "allOf"
  case anyOf = "anyOf"
  case oneOf = "oneOf"
  case not = "not"
  case `enum` = "enum"
  case maximumLength = "maxLength"
  case minimumLength = "minLength"
  case pattern = "pattern"
  case multipleOf = "multipleOf"
  case minimum = "minimum"
  case maximum = "maximum"
  case minimumItems = "minItems"
  case maximumItems = "maxItems"
  case exclusiveMinimum = "exclusiveMinimum"
  case exclusiveMaximum = "exclusiveMaximum"
  case uniqueItems = "uniqueItems"
  case items = "items"
  case additionalItems = "additionalItems"
  case maximumProperties = "maxProperties"
  case minimumProperties = "minProperties"
  case required = "required"
  case properties = "properties"
  case patternProperties = "patternProperties"
  case additionalProperties = "additionalProperties"
  case dependencies = "dependencies"
  case format = "format"
}

public typealias JSON = [String: Any]

public struct SchemaType {
  let data: [String: Any]
  public init(_ data: [String: Any]) {
    self.data = data
  }
  
  public subscript(key: SchemaKey) -> Any? {
    return data[key.rawValue]
  }
}

public struct Schema {
  public let title:       String?
  public let description: String?
  public let type:        [Type]?
  public let properties:  JSON?
  
  /// validation formats, currently private. If anyone wants to add custom please make a PR to make this public ;)
  let formats: [String: Validator]
  let schema:  SchemaType
  
  public init(_ schema: SchemaType) {
    self.schema      = schema
    self.title       = schema[.title]       as? String
    self.description = schema[.description] as? String
    self.properties  = schema[.properties]  as? JSON
    
    if let type = schema[.type] as? String {
      self.type = Type(rawValue: type).map { [$0] } ?? []
    } else if let types = schema[.type] as? [String] {
      self.type = types.flatMap { Type(rawValue: $0) }
    } else {
      self.type = []
    }
    
    self.formats = [
      "ipv4": validateIPv4,
      "ipv6": validateIPv6,
    ]
  }
  
  public func validate(_ data: Any) -> ValidationResult {
    let validator = allOf(validators(self)(schema))
    let result = validator(data)
    return result
  }
  
  func validator(for reference: String) -> Validator {
    // TODO: Rewrite this whole block: https://github.com/kylef/JSONSchema.swift/issues/12
    
    if let reference = reference.removePrefix("#") {  // Document relative
      if let tmp = reference.removePrefix("/"), let reference = (tmp as NSString).removingPercentEncoding {
        var components = reference.components(separatedBy: "/")
        var schema = self.schema
        while let c = components.first, let component = SchemaKey(rawValue: c) {
          components.remove(at: components.startIndex)
          
          if let subschema = schema[component] as? JSON {
            schema = SchemaType(subschema)
            continue
          } else if let schemas = schema[component] as? [JSON] {
            if let component = components.first, let index = Int(component) {
              components.remove(at: components.startIndex)
              
              if schemas.count > index {
                schema = SchemaType(schemas[index])
                continue
              }
            }
          }
          
          return invalidValidation(ReferenceNotFoundError(reference: reference, component: component))
        }
        
        return allOf(JSONSchema.validators(self)(schema))
      } else if reference == "" {
        return { value in
          let validators = JSONSchema.validators(self)(self.schema)
          return allOf(validators)(value)
        }
      }
    }
    
    return invalidValidation(RemoteReferenceUnsupportedError(reference: reference))
  }
}

/// Returns a set of validators for a schema and document
func validators(_ root: Schema) -> (_ schema: SchemaType) -> [Validator] {
  return { schema in
    var validators = [Validator]()
    
    if let ref = schema[.reference] as? String {
      validators.append(root.validator(for: ref))
    }
    
    if let type = schema[.type] {
      // Rewrite this and most of the validator to use the `type` property, see https://github.com/kylef/JSONSchema.swift/issues/12
      validators.append(validateType(type))
    }
    
    if let allOf = schema[.allOf] as? [JSON] {
      validators += allOf
        .map { SchemaType($0) }
        .map(JSONSchema.validators(root))
        .reduce([], +)
    }
    
    if let anyOfSchemas = schema[.anyOf] as? [JSON] {
      let anyOfValidators = anyOfSchemas
        .map { SchemaType($0) }
        .map(JSONSchema.validators(root))
        .map(allOf) as [Validator]
      
      validators.append(anyOf(anyOfValidators))
    }
    
    if let oneOfSchemas = schema[.oneOf] as? [JSON] {
      let oneOfValidators = oneOfSchemas
        .map { SchemaType($0) }
        .map(JSONSchema.validators(root))
        .map(allOf) as [Validator]
      validators.append(oneOf(oneOfValidators))
    }
    
    if let notSchema = schema[.not] as? JSON {
      let notValidator = allOf(JSONSchema.validators(root)(SchemaType(notSchema)))
      validators.append(not(notValidator))
    }
    
    if let enumValues = schema[.enum] as? [Any] {
      validators.append(validateEnum(enumValues))
    }
    
    // String
    
    if let maxLength = schema[.maximumLength] as? Int {
      validators.append(validateLength(<=, length: maxLength, error: LengthError(length: maxLength, itemType: .string, comparison: .tooLarge)))
    }
    
    if let minLength = schema[.minimumLength] as? Int {
      validators.append(validateLength(>=, length: minLength, error: LengthError(length: minLength, itemType: .string, comparison: .tooSmall)))
    }
    
    if let pattern = schema[.pattern] as? String {
      validators.append(validatePattern(pattern))
    }
    
    // Numerical
    
    if let multipleOf = schema[.multipleOf] as? Double {
      validators.append(validateMultipleOf(multipleOf))
    }
    
    if let minimum = schema[.minimum] as? Double {
      validators.append(validateNumericLength(minimum, comparator: >=, exclusiveComparator: >, exclusive: schema[.exclusiveMinimum] as? Bool, error: ValueBoundsError(bounds: minimum, comparison: .tooSmall)))
    }
    
    if let maximum = schema[.maximum] as? Double {
      validators.append(validateNumericLength(maximum, comparator: <=, exclusiveComparator: <, exclusive: schema[.exclusiveMaximum] as? Bool, error: ValueBoundsError(bounds: maximum, comparison: .tooLarge)))
    }
    
    // Array
    
    if let minItems = schema[.minimumItems] as? Int {
      validators.append(validateArrayLength(minItems, comparator: >=, error: LengthError(length: minItems, itemType: .array, comparison: .tooSmall)))
    }
    
    if let maxItems = schema[.maximumItems] as? Int {
      validators.append(validateArrayLength(maxItems, comparator: <=, error: LengthError(length: maxItems, itemType: .array, comparison: .tooLarge)))
    }
    
    if let uniqueItems = schema[.uniqueItems] as? Bool {
      if uniqueItems {
        validators.append(validateUniqueItems)
      }
    }
    
    if let items = schema[.items] as? JSON {
      let itemsValidators = allOf(JSONSchema.validators(root)(SchemaType(items)))
      
      func validateItems(_ document: Any) -> ValidationResult {
        if let document = document as? [Any] {
          return document.map(itemsValidators).flattened()
        }
        
        return .valid
      }
      
      validators.append(validateItems)
    } else if let items = schema[.items] as? [JSON] {
      func createAdditionalItemsValidator(_ additionalItems: Any?) -> Validator {
        if let additionalItems = additionalItems as? JSON {
          return allOf(JSONSchema.validators(root)(SchemaType(additionalItems)))
        }
        
        let additionalItems = additionalItems as? Bool ?? true
        if additionalItems {
          return validValidation
        }
        
        return invalidValidation(AdditionalPropertiesError(itemType: .array))
      }
      
      let additionalItemsValidator = createAdditionalItemsValidator(schema[.additionalItems])
      let itemValidators = items.map { SchemaType($0) }.map(JSONSchema.validators(root))
      
      func validateItems(_ value: Any) -> ValidationResult {
        if let value = value as? [Any] {
          var results = [ValidationResult]()
          
          for (index, element) in value.enumerated() {
            if index >= itemValidators.count {
              results.append(additionalItemsValidator(element))
            } else {
              let validators = allOf(itemValidators[index])
              results.append(validators(element))
            }
          }
          
          return results.flattened()
        }
        
        return .valid
      }
      
      validators.append(validateItems)
    }
    
    if let maxProperties = schema[.maximumProperties] as? Int {
      validators.append(validatePropertiesLength(maxProperties, comparator: >=, error: LengthError(length: maxProperties, itemType: .properties, comparison: .tooLarge)))
    }
    
    if let minProperties = schema[.minimumProperties] as? Int {
      validators.append(validatePropertiesLength(minProperties, comparator: <=, error: LengthError(length: minProperties, itemType: .properties, comparison: .tooSmall)))
    }
    
    if let required = schema[.required] as? [String] {
      validators.append(validateRequired(required))
    }
    
    if (schema[.properties] != nil) || (schema[.patternProperties] != nil) || (schema[.additionalProperties] != nil) {
      func createAdditionalPropertiesValidator(_ additionalProperties: Any?) -> Validator {
        if let additionalProperties = additionalProperties as? JSON {
          return allOf(JSONSchema.validators(root)(SchemaType(additionalProperties)))
        }
        
        let additionalProperties = additionalProperties as? Bool ?? true
        if additionalProperties {
          return validValidation
        }
        
        return invalidValidation(AdditionalPropertiesError(itemType: .object))
      }
      
      func createPropertiesValidators(_ properties: [String: JSON]?) -> [String: Validator]? {
        if let properties = properties {
          return Dictionary(properties.map { key, value in
            (key, allOf(JSONSchema.validators(root)(SchemaType(value))))
          })
        }
        
        return nil
      }
      
      let additionalPropertyValidator = createAdditionalPropertiesValidator(schema[.additionalProperties])
      let properties = createPropertiesValidators(schema[.properties] as? [String: JSON])
      let patternProperties = createPropertiesValidators(schema[.patternProperties] as? [String: JSON])
      validators.append(validateProperties(properties, patternProperties: patternProperties, additionalProperties: additionalPropertyValidator))
    }
    
    func validateDependency(_ key: String, validator: @escaping Validator) -> (_ value: Any) -> ValidationResult {
      return { value in
        if let value = value as? JSON, let _ = value[key] {
          return validator(value)
        }
        return .valid
      }
    }
    
    func validateDependencies(_ key: String, dependencies: [String]) -> (_ value: Any) -> ValidationResult {
      return { value in
        if let value = value as? JSON, let _ = value[key] {
          return dependencies.map { dependency in
            if value[dependency] == nil {
              return .invalid([DependencyMissingError(key: key, dependency: dependency)])
            }
            return .valid
            }.flattened()
        }
        return .valid
      }
    }
    
    if let dependencies = schema[.dependencies] as? JSON {
      for (key, dependencies) in dependencies {
        if let dependencies = dependencies as? JSON {
          let schema = allOf(JSONSchema.validators(root)(SchemaType(dependencies)))
          validators.append(validateDependency(key, validator: schema))
        } else if let dependencies = dependencies as? [String] {
          validators.append(validateDependencies(key, dependencies: dependencies))
        }
      }
    }
    
    if let format = schema[.format] as? String {
      if let validator = root.formats[format] {
        validators.append(validator)
      } else {
        validators.append(invalidValidation(FormatUnsupportedError(format: format)))
      }
    }
    
    return validators
  }
}

public func validate(_ value: Any, schema: SchemaType) -> ValidationResult {
  let root = Schema(schema)
  let validator = allOf(validators(root)(schema))
  let result = validator(value)
  return result
}

/// Extension for dictionary providing initialization from array of elements
extension Dictionary {
  init(_ pairs: [Element]) {
    self.init()
    
    for (key, value) in pairs {
      self[key] = value
    }
  }
}
