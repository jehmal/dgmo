/**
 * Type conversion utilities for cross-language tool integration
 */

import { z } from 'zod';

export class TypeConverter {
  /**
   * Convert Python types to TypeScript types
   */
  static pythonToTypeScript(value: any): any {
    if (value === null || value === undefined) {
      return value;
    }

    // Handle None -> null
    if (value === 'None') {
      return null;
    }

    // Handle True/False -> boolean
    if (value === 'True') return true;
    if (value === 'False') return false;

    // Handle tuples -> arrays
    if (Array.isArray(value) && value.__type__ === 'tuple') {
      delete value.__type__;
      return value;
    }

    // Handle sets -> arrays
    if (value.__type__ === 'set') {
      return Array.from(value.items || []);
    }

    // Handle datetime -> ISO string
    if (value.__type__ === 'datetime') {
      return value.isoformat || value.toString();
    }

    // Handle Decimal -> number
    if (value.__type__ === 'Decimal') {
      return parseFloat(value.value);
    }

    // Recursively handle objects
    if (typeof value === 'object' && !Array.isArray(value)) {
      const converted: any = {};
      for (const [key, val] of Object.entries(value)) {
        converted[key] = this.pythonToTypeScript(val);
      }
      return converted;
    }

    // Recursively handle arrays
    if (Array.isArray(value)) {
      return value.map((item) => this.pythonToTypeScript(item));
    }

    return value;
  }

  /**
   * Convert TypeScript types to Python types
   */
  static typeScriptToPython(value: any): any {
    if (value === null || value === undefined) {
      return null;
    }

    // Handle undefined -> None
    if (value === undefined) {
      return null;
    }

    // Handle Date -> datetime string
    if (value instanceof Date) {
      return {
        __type__: 'datetime',
        isoformat: value.toISOString(),
      };
    }

    // Handle Set -> set
    if (value instanceof Set) {
      return {
        __type__: 'set',
        items: Array.from(value),
      };
    }

    // Handle Map -> dict
    if (value instanceof Map) {
      const obj: any = {};
      for (const [key, val] of value.entries()) {
        obj[String(key)] = this.typeScriptToPython(val);
      }
      return obj;
    }

    // Handle BigInt -> string
    if (typeof value === 'bigint') {
      return value.toString();
    }

    // Handle Buffer/Uint8Array -> bytes
    if (value instanceof Buffer || value instanceof Uint8Array) {
      return {
        __type__: 'bytes',
        data: Array.from(value),
      };
    }

    // Recursively handle objects
    if (typeof value === 'object' && !Array.isArray(value)) {
      const converted: any = {};
      for (const [key, val] of Object.entries(value)) {
        converted[key] = this.typeScriptToPython(val);
      }
      return converted;
    }

    // Recursively handle arrays
    if (Array.isArray(value)) {
      return value.map((item) => this.typeScriptToPython(item));
    }

    return value;
  }

  /**
   * Convert JSON Schema to Zod schema
   */
  static jsonSchemaToZod(schema: any): z.ZodSchema {
    if (!schema || typeof schema !== 'object') {
      return z.any();
    }

    switch (schema.type) {
      case 'string':
        let stringSchema = z.string();
        if (schema.minLength) stringSchema = stringSchema.min(schema.minLength);
        if (schema.maxLength) stringSchema = stringSchema.max(schema.maxLength);
        if (schema.pattern) stringSchema = stringSchema.regex(new RegExp(schema.pattern));
        if (schema.enum) return z.enum(schema.enum as [string, ...string[]]);
        return stringSchema;

      case 'number':
      case 'integer':
        let numberSchema = schema.type === 'integer' ? z.number().int() : z.number();
        if (schema.minimum !== undefined) numberSchema = numberSchema.min(schema.minimum);
        if (schema.maximum !== undefined) numberSchema = numberSchema.max(schema.maximum);
        return numberSchema;

      case 'boolean':
        return z.boolean();

      case 'array':
        const itemSchema = schema.items ? this.jsonSchemaToZod(schema.items) : z.any();
        let arraySchema = z.array(itemSchema);
        if (schema.minItems) arraySchema = arraySchema.min(schema.minItems);
        if (schema.maxItems) arraySchema = arraySchema.max(schema.maxItems);
        return arraySchema;

      case 'object':
        if (schema.properties) {
          const shape: Record<string, z.ZodSchema> = {};
          for (const [key, propSchema] of Object.entries(schema.properties)) {
            shape[key] = this.jsonSchemaToZod(propSchema);
          }

          let objectSchema = z.object(shape);

          // Handle required fields
          if (schema.required && Array.isArray(schema.required)) {
            // Mark non-required fields as optional
            for (const key of Object.keys(shape)) {
              if (!schema.required.includes(key)) {
                shape[key] = shape[key].optional();
              }
            }
            objectSchema = z.object(shape);
          }

          // Handle additionalProperties
          if (schema.additionalProperties === false) {
            objectSchema = objectSchema.strict();
          }

          return objectSchema;
        }
        return z.record(z.any());

      case 'null':
        return z.null();

      default:
        // Handle anyOf, oneOf, allOf
        if (schema.anyOf) {
          const schemas = schema.anyOf.map((s: any) => this.jsonSchemaToZod(s));
          return z.union(schemas as [z.ZodSchema, z.ZodSchema, ...z.ZodSchema[]]);
        }

        if (schema.oneOf) {
          const schemas = schema.oneOf.map((s: any) => this.jsonSchemaToZod(s));
          return z.union(schemas as [z.ZodSchema, z.ZodSchema, ...z.ZodSchema[]]);
        }

        if (schema.allOf) {
          // This is a simplification - proper allOf handling is complex
          const schemas = schema.allOf.map((s: any) => this.jsonSchemaToZod(s));
          return schemas[0]; // Take the first schema as approximation
        }

        return z.any();
    }
  }

  /**
   * Convert Zod schema to JSON Schema
   */
  static zodToJsonSchema(schema: z.ZodSchema): any {
    const def = schema._def;

    if (def.typeName === 'ZodString') {
      const jsonSchema: any = { type: 'string' };
      if (def.checks) {
        for (const check of def.checks) {
          if (check.kind === 'min') jsonSchema.minLength = check.value;
          if (check.kind === 'max') jsonSchema.maxLength = check.value;
          if (check.kind === 'regex') jsonSchema.pattern = check.regex.source;
        }
      }
      return jsonSchema;
    }

    if (def.typeName === 'ZodNumber') {
      const jsonSchema: any = { type: 'number' };
      if (def.checks) {
        for (const check of def.checks) {
          if (check.kind === 'min') jsonSchema.minimum = check.value;
          if (check.kind === 'max') jsonSchema.maximum = check.value;
          if (check.kind === 'int') jsonSchema.type = 'integer';
        }
      }
      return jsonSchema;
    }

    if (def.typeName === 'ZodBoolean') {
      return { type: 'boolean' };
    }

    if (def.typeName === 'ZodArray') {
      return {
        type: 'array',
        items: this.zodToJsonSchema(def.type),
      };
    }

    if (def.typeName === 'ZodObject') {
      const properties: any = {};
      const required: string[] = [];

      for (const [key, value] of Object.entries(def.shape())) {
        properties[key] = this.zodToJsonSchema(value as z.ZodSchema);

        // Check if field is required
        if (!(value as any).isOptional()) {
          required.push(key);
        }
      }

      return {
        type: 'object',
        properties,
        required: required.length > 0 ? required : undefined,
        additionalProperties: def.strict === true ? false : true,
      };
    }

    if (def.typeName === 'ZodNull') {
      return { type: 'null' };
    }

    if (def.typeName === 'ZodUnion') {
      return {
        anyOf: def.options.map((option: z.ZodSchema) => this.zodToJsonSchema(option)),
      };
    }

    if (def.typeName === 'ZodEnum') {
      return {
        type: 'string',
        enum: def.values,
      };
    }

    if (def.typeName === 'ZodOptional') {
      const innerSchema = this.zodToJsonSchema(def.innerType);
      return {
        ...innerSchema,
        nullable: true,
      };
    }

    // Default fallback
    return { type: 'any' };
  }

  /**
   * Validate value against schema with type coercion
   */
  static validateAndCoerce(value: any, schema: any, fromLanguage: 'python' | 'typescript'): any {
    // Convert value based on source language
    const converted =
      fromLanguage === 'python' ? this.pythonToTypeScript(value) : this.typeScriptToPython(value);

    // If schema is a Zod schema, use Zod validation
    if (schema && typeof schema === 'object' && schema._def) {
      const result = schema.safeParse(converted);

      if (!result.success) {
        throw new Error(`Validation failed: ${result.error.message}`);
      }

      return result.data;
    }

    // Otherwise, assume it's a JSON schema and do basic validation
    // In production, use a proper JSON schema validator
    return converted;
  }

  /**
   * Convert DGMO tool parameters to DGM format
   */
  static dgmoToDgmToolParams(dgmoParams: any): any {
    // DGMO uses Zod schemas, DGM uses JSON schemas
    if (dgmoParams && dgmoParams._def) {
      return this.zodToJsonSchema(dgmoParams);
    }
    return dgmoParams;
  }

  /**
   * Convert DGM tool parameters to DGMO format
   */
  static dgmToDgmoToolParams(dgmParams: any): any {
    // DGM uses JSON schemas, DGMO uses Zod schemas
    if (dgmParams && typeof dgmParams === 'object' && 'type' in dgmParams) {
      return this.jsonSchemaToZod(dgmParams);
    }
    return dgmParams;
  }

  /**
   * Convert DGMO tool result to DGM format
   */
  static dgmoToDgmResult(result: { metadata: Record<string, any>; output: string }): any {
    return {
      output: result.output,
      metadata: result.metadata,
      success: true,
    };
  }

  /**
   * Convert DGM tool result to DGMO format
   */
  static dgmToDgmoResult(result: any): { metadata: Record<string, any>; output: string } {
    if (typeof result === 'string') {
      return {
        output: result,
        metadata: {},
      };
    }

    return {
      output: result.output || JSON.stringify(result),
      metadata: result.metadata || {},
    };
  }

  /**
   * Deep merge objects (useful for combining tool configs)
   */
  static deepMerge(target: any, source: any): any {
    const output = { ...target };

    if (isObject(target) && isObject(source)) {
      Object.keys(source).forEach((key) => {
        if (isObject(source[key])) {
          if (!(key in target)) {
            Object.assign(output, { [key]: source[key] });
          } else {
            output[key] = this.deepMerge(target[key], source[key]);
          }
        } else {
          Object.assign(output, { [key]: source[key] });
        }
      });
    }

    return output;
  }
}

function isObject(item: any): boolean {
  return item && typeof item === 'object' && !Array.isArray(item);
}
