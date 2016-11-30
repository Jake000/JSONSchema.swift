//
//  JSONSchema.swift
//  JSONSchema
//
//  Created by Kyle Fuller on 07/03/2015.
//  Copyright (c) 2015 Cocode. All rights reserved.
//

import Foundation

public enum Type: String {
  case object = "object"
  case array = "array"
  case string = "string"
  case integer = "integer"
  case number = "number"
  case boolean = "boolean"
  case null = "null"
}

extension String {
  func removePrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let index = characters.index(startIndex, offsetBy: prefix.characters.count)
    return substring(from: index)
  }
}

public struct Schema {
  public let title:String?
  public let description:String?
  
  public let type: [Type]?
  
  /// validation formats, currently private. If anyone wants to add custom please make a PR to make this public ;)
  let formats: [String: Validator]
  
  let schema: [String: Any]
  
  public init(_ schema: [String: Any]) {
    title = schema["title"] as? String
    description = schema["description"] as? String
    
    if let type = schema["type"] as? String {
      if let type = Type(rawValue: type) {
        self.type = [type]
      } else {
        self.type = []
      }
    } else if let types = schema["type"] as? [String] {
      self.type = types.map { Type(rawValue: $0) }.filter { $0 != nil }.map { $0! }
    } else {
      self.type = []
    }
    
    self.schema = schema
    
    formats = [
      "ipv4": validateIPv4,
      "ipv6": validateIPv6,
    ]
  }
  
  public func validate(_ data: Any) -> ValidationResult {
    let validator = allOf(validators(self)(schema))
    let result = validator(data)
    return result
  }
  
  func validator(for reference:String) -> Validator {
    // TODO: Rewrite this whole block: https://github.com/kylef/JSONSchema.swift/issues/12
    
    if let reference = reference.removePrefix("#") {  // Document relative
      if let tmp = reference.removePrefix("/"), let reference = (tmp as NSString).removingPercentEncoding {
        var components = reference.components(separatedBy: "/")
        var schema = self.schema
        while let component = components.first {
          components.remove(at: components.startIndex)
          
          if let subschema = schema[component] as? [String: Any] {
            schema = subschema
            continue
          } else if let schemas = schema[component] as? [[String: Any]] {
            if let component = components.first, let index = Int(component) {
              components.remove(at: components.startIndex)
              
              if schemas.count > index {
                schema = schemas[index]
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
func validators(_ root: Schema) -> (_ schema: [String: Any]) -> [Validator] {
  return { schema in
    var validators = [Validator]()
    
    if let ref = schema["$ref"] as? String {
      validators.append(root.validator(for: ref))
    }
    
    if let type = schema["type"] {
      // Rewrite this and most of the validator to use the `type` property, see https://github.com/kylef/JSONSchema.swift/issues/12
      validators.append(validateType(type))
    }
    
    if let allOf = schema["allOf"] as? [[String: Any]] {
      validators += allOf.map(JSONSchema.validators(root)).reduce([], +)
    }
    
    if let anyOfSchemas = schema["anyOf"] as? [[String: Any]] {
      let anyOfValidators = anyOfSchemas.map(JSONSchema.validators(root)).map(allOf) as [Validator]
      validators.append(anyOf(anyOfValidators))
    }
    
    if let oneOfSchemas = schema["oneOf"] as? [[String: Any]] {
      let oneOfValidators = oneOfSchemas.map(JSONSchema.validators(root)).map(allOf) as [Validator]
      validators.append(oneOf(oneOfValidators))
    }
    
    if let notSchema = schema["not"] as? [String: Any] {
      let notValidator = allOf(JSONSchema.validators(root)(notSchema))
      validators.append(not(notValidator))
    }
    
    if let enumValues = schema["enum"] as? [Any] {
      validators.append(validateEnum(enumValues))
    }
    
    // String
    
    if let maxLength = schema["maxLength"] as? Int {
      validators.append(validateLength(<=, length: maxLength, error: LengthError(length: maxLength, itemType: .string, comparison: .tooLarge)))
    }
    
    if let minLength = schema["minLength"] as? Int {
      validators.append(validateLength(>=, length: minLength, error: LengthError(length: minLength, itemType: .string, comparison: .tooSmall)))
    }
    
    if let pattern = schema["pattern"] as? String {
      validators.append(validatePattern(pattern))
    }
    
    // Numerical
    
    if let multipleOf = schema["multipleOf"] as? Double {
      validators.append(validateMultipleOf(multipleOf))
    }
    
    if let minimum = schema["minimum"] as? Double {
      validators.append(validateNumericLength(minimum, comparator: >=, exclusiveComparator: >, exclusive: schema["exclusiveMinimum"] as? Bool, error: ValueBoundsError(bounds: minimum, comparison: .tooSmall)))
    }
    
    if let maximum = schema["maximum"] as? Double {
      validators.append(validateNumericLength(maximum, comparator: <=, exclusiveComparator: <, exclusive: schema["exclusiveMaximum"] as? Bool, error: ValueBoundsError(bounds: maximum, comparison: .tooLarge)))
    }
    
    // Array
    
    if let minItems = schema["minItems"] as? Int {
      validators.append(validateArrayLength(minItems, comparator: >=, error: LengthError(length: minItems, itemType: .array, comparison: .tooSmall)))
    }
    
    if let maxItems = schema["maxItems"] as? Int {
      validators.append(validateArrayLength(maxItems, comparator: <=, error: LengthError(length: maxItems, itemType: .array, comparison: .tooLarge)))
    }
    
    if let uniqueItems = schema["uniqueItems"] as? Bool {
      if uniqueItems {
        validators.append(validateUniqueItems)
      }
    }
    
    if let items = schema["items"] as? [String: Any] {
      let itemsValidators = allOf(JSONSchema.validators(root)(items))
      
      func validateItems(_ document: Any) -> ValidationResult {
        if let document = document as? [Any] {
          return document.map(itemsValidators).flattened()
        }
        
        return .valid
      }
      
      validators.append(validateItems)
    } else if let items = schema["items"] as? [[String: Any]] {
      func createAdditionalItemsValidator(_ additionalItems: Any?) -> Validator {
        if let additionalItems = additionalItems as? [String: Any] {
          return allOf(JSONSchema.validators(root)(additionalItems))
        }
        
        let additionalItems = additionalItems as? Bool ?? true
        if additionalItems {
          return validValidation
        }
        
        return invalidValidation(AdditionalPropertiesError(itemType: .array))
      }
      
      let additionalItemsValidator = createAdditionalItemsValidator(schema["additionalItems"])
      let itemValidators = items.map(JSONSchema.validators(root))
      
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
    
    if let maxProperties = schema["maxProperties"] as? Int {
      validators.append(validatePropertiesLength(maxProperties, comparator: >=, error: LengthError(length: maxProperties, itemType: .properties, comparison: .tooLarge)))
    }
    
    if let minProperties = schema["minProperties"] as? Int {
      validators.append(validatePropertiesLength(minProperties, comparator: <=, error: LengthError(length: minProperties, itemType: .properties, comparison: .tooSmall)))
    }
    
    if let required = schema["required"] as? [String] {
      validators.append(validateRequired(required))
    }
    
    if (schema["properties"] != nil) || (schema["patternProperties"] != nil) || (schema["additionalProperties"] != nil) {
      func createAdditionalPropertiesValidator(_ additionalProperties: Any?) -> Validator {
        if let additionalProperties = additionalProperties as? [String: Any] {
          return allOf(JSONSchema.validators(root)(additionalProperties))
        }
        
        let additionalProperties = additionalProperties as? Bool ?? true
        if additionalProperties {
          return validValidation
        }
        
        return invalidValidation(AdditionalPropertiesError(itemType: .object))
      }
      
      func createPropertiesValidators(_ properties: [String: [String: Any]]?) -> [String: Validator]? {
        if let properties = properties {
          return Dictionary(properties.keys.map {
            key in (key, allOf(JSONSchema.validators(root)(properties[key]!)))
          })
        }
        
        return nil
      }
      
      let additionalPropertyValidator = createAdditionalPropertiesValidator(schema["additionalProperties"])
      let properties = createPropertiesValidators(schema["properties"] as? [String: [String: Any]])
      let patternProperties = createPropertiesValidators(schema["patternProperties"] as? [String: [String: Any]])
      validators.append(validateProperties(properties, patternProperties: patternProperties, additionalProperties: additionalPropertyValidator))
    }
    
    func validateDependency(_ key: String, validator: @escaping Validator) -> (_ value: Any) -> ValidationResult {
      return { value in
        if let value = value as? [String: Any], let _ = value[key] {
          return validator(value)
        }
        return .valid
      }
    }
    
    func validateDependencies(_ key: String, dependencies: [String]) -> (_ value: Any) -> ValidationResult {
      return { value in
        if let value = value as? [String: Any], let _ = value[key] {
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
    
    if let dependencies = schema["dependencies"] as? [String: Any] {
      for (key, dependencies) in dependencies {
        if let dependencies = dependencies as? [String: Any] {
          let schema = allOf(JSONSchema.validators(root)(dependencies))
          validators.append(validateDependency(key, validator: schema))
        } else if let dependencies = dependencies as? [String] {
          validators.append(validateDependencies(key, dependencies: dependencies))
        }
      }
    }
    
    if let format = schema["format"] as? String {
      if let validator = root.formats[format] {
        validators.append(validator)
      } else {
        validators.append(invalidValidation(FormatUnsupportedError(format: format)))
      }
    }
    
    return validators
  }
}

public func validate(_ value: Any, schema: [String: Any]) -> ValidationResult {
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
