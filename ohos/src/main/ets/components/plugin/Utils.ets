import { Any, ToolUtils } from '@ohos/flutter_ohos';
import { JSON } from '@kit.ArkTS';
import { UIContext } from '@ohos.arkui.UIContext';

export type JsonMap = Map<string, Any>;

export function findValue(args: Any, key: string): Any {
  if (args == null) {
    return null;
  } else if (args instanceof Map) {
    return (args as Map<Any, Any>).get(key);
  } else if (ToolUtils.isObj(args)) {
    return args[key];
  } else {
    throw new Error("ClassCastException");
  }
}

export function getStringOrNull(value: Any): string | null {
  if (typeof value === "string") {
    return value;
  }
  if (value instanceof String) {
    return value.valueOf();
  }
  return null
}

export function getString(value: Any, defaultValue: string | null = null): string {
  return getStringOrNull(value) ?? defaultValue ?? "";
}

export function findStringOrNull(args: Any, key: string): string | null {
  const value: Any = findValue(args, key);
  return getStringOrNull(value);
}

export function findString(args: Any, key: string, defaultValue: string | null = null): string {
  return findStringOrNull(args, key) ?? defaultValue ?? "";
}

export function getNumberOrNull(value: Any): number | null {
  if (typeof value === "number") {
    return value;
  }
  if (value instanceof Number) {
    return value.valueOf();
  }
  return null;
}

export function getNumber(value: Any, defaultValue: number | null = null): number {
  return getNumberOrNull(value) ?? defaultValue ?? 0;
}

export function findNumberOrNull(args: Any, key: string): number | null {
  const value: Any = findValue(args, key);
  return getNumberOrNull(value);
}

export function findNumber(args: Any, key: string, defaultValue: number | null = null): number {
  return findNumberOrNull(args, key) ?? defaultValue ?? 0;
}

export function findBoolOrNull(args: Any, key: string): boolean | null {
  const value: Any = findValue(args, key);
  if (typeof value === "boolean") {
    return value;
  }
  if (value instanceof Boolean) {
    return value.valueOf();
  }
  return null;
}

export function findBool(args: Any, key: string): boolean {
  return findBoolOrNull(args, key) ?? false;
}

export function findArray(args: Any, key: string, defaultValue: Any[] | null = null): Any[] {
  const value: Any = findValue(args, key);
  if (Array.isArray(value)) {
    return value as Any[];
  }
  if (value instanceof Array) {
    return value as Any[]
  }
  return defaultValue ?? [];
}

export function findMap(args: Any, key: string, defaultValue: Map<Any, Any> | null = null): Map<Any, Any> {
  const value: Any = findValue(args, key);
  if (value instanceof Map) {
    return value;
  }
  return defaultValue ?? new Map<Any, Any>();
}

export function hasKey(args: Any, key: string): boolean {
  if (args == null) {
    return false;
  } else if (args instanceof Map) {
    return (args as Map<Any, Any>).has(key);
  } else if (ToolUtils.isObj(args)) {
    return args.hasOwnProperty(key);
  } else {
    throw new Error("ClassCastException");
  }
}

export function toJsonReady(data: Any): Any {
  // 处理 Map：转换为普通对象
  if (data instanceof Map) {
    const obj: Record<string, Any> = {};
    data.forEach((value: Any, key: Any) => {
      const strKey = String(key); // 键转字符串
      obj[strKey] = toJsonReady(value); // 递归处理值（可能是数组或嵌套 Map）
    })

    return obj;
  }

  // 处理数组：遍历每个元素并递归转换
  if (Array.isArray(data)) {
    return data.map(toJsonReady); // 递归处理数组中的每个元素
  }

  // 其他类型（基本类型、普通对象等）直接返回（需确保可 JSON 序列化）
  return data;
}

export function dump(args: Any): string {
  let obj: Any = toJsonReady(args);
  return JSON.stringify(obj);
}

export function isNull(value: Any) {
  return value == null || value == undefined;
}

export namespace contextUtils {
  export function getUIContext(): UIContext | undefined {
    return AppStorage.get("context") as UIContext | undefined;
  }
}
