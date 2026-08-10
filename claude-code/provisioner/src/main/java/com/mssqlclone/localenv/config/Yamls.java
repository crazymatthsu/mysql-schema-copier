package com.mssqlclone.localenv.config;

import java.util.List;
import java.util.Map;

/**
 * Small typed accessors over the maps SnakeYAML produces.
 *
 * <p>Mapping by hand rather than binding to bean classes keeps the failure message
 * pointing at the offending key in {@code databases.yaml}, which is the file a developer
 * will actually be editing.
 */
final class Yamls {

    private Yamls() {
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> requireMap(Object value, String path) {
        if (!(value instanceof Map<?, ?> map)) {
            throw new ConfigException(path + ": expected a mapping, found "
                    + (value == null ? "nothing" : value.getClass().getSimpleName()));
        }
        return (Map<String, Object>) map;
    }

    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> requireMapList(Object value, String path) {
        if (!(value instanceof List<?> list)) {
            throw new ConfigException(path + ": expected a list, found "
                    + (value == null ? "nothing" : value.getClass().getSimpleName()));
        }
        for (Object element : list) {
            requireMap(element, path + "[]");
        }
        return (List<Map<String, Object>>) list;
    }

    static List<Map<String, Object>> optionalMapList(Map<String, Object> map, String key, String path) {
        Object value = map.get(key);
        return value == null ? List.of() : requireMapList(value, path + "." + key);
    }

    static String requireString(Map<String, Object> map, String key, String path) {
        Object value = map.get(key);
        if (value == null || value.toString().isBlank()) {
            throw new ConfigException(path + "." + key + ": required value is missing");
        }
        return value.toString();
    }

    static String optionalString(Map<String, Object> map, String key, String fallback) {
        Object value = map.get(key);
        return value == null ? fallback : value.toString();
    }

    static int requireInt(Map<String, Object> map, String key, String path) {
        Object value = map.get(key);
        if (value == null) {
            throw new ConfigException(path + "." + key + ": required value is missing");
        }
        if (value instanceof Number number) {
            return number.intValue();
        }
        try {
            return Integer.parseInt(value.toString().trim());
        } catch (NumberFormatException e) {
            throw new ConfigException(path + "." + key + ": expected a whole number, found '" + value + "'");
        }
    }

    static int optionalInt(Map<String, Object> map, String key, int fallback) {
        Object value = map.get(key);
        if (value == null) {
            return fallback;
        }
        if (value instanceof Number number) {
            return number.intValue();
        }
        return Integer.parseInt(value.toString().trim());
    }

    static boolean optionalBoolean(Map<String, Object> map, String key, boolean fallback) {
        Object value = map.get(key);
        if (value == null) {
            return fallback;
        }
        if (value instanceof Boolean bool) {
            return bool;
        }
        return Boolean.parseBoolean(value.toString().trim());
    }

    @SuppressWarnings("unchecked")
    static List<String> optionalStringList(Map<String, Object> map, String key) {
        Object value = map.get(key);
        if (value == null) {
            return List.of();
        }
        if (!(value instanceof List<?> list)) {
            throw new ConfigException(key + ": expected a list of strings");
        }
        return ((List<Object>) list).stream().map(Object::toString).toList();
    }
}
