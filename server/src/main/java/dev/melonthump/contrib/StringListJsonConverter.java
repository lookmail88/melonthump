package dev.melonthump.contrib;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import java.util.List;

/**
 * Stores a list of strings as a JSON array in a TEXT column — portable
 * between PostgreSQL and H2 (no PG array / jsonb dependency).
 */
@Converter
public class StringListJsonConverter implements AttributeConverter<List<String>, String> {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final TypeReference<List<String>> LIST = new TypeReference<>() {
    };

    @Override
    public String convertToDatabaseColumn(List<String> value) {
        if (value == null) {
            return null;
        }
        try {
            return JSON.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("cannot encode string list", e);
        }
    }

    @Override
    public List<String> convertToEntityAttribute(String column) {
        if (column == null) {
            return null;
        }
        try {
            return JSON.readValue(column, LIST);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("stored value is not a JSON string array", e);
        }
    }
}
