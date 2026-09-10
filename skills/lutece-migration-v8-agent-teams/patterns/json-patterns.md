# JSON: json-lib to Jackson

Lutece 8 removed `net.sf.json` (json-lib). Use Jackson, already provided by the core. `fr.paris.lutece.util.json.JsonUtil` offers static `serialize()` / `deserialize()` helpers for the common cases. Share one `ObjectMapper` per class, never create one per call.

### Import Changes

```java
// v7
import net.sf.json.JSON;
import net.sf.json.JSONArray;
import net.sf.json.JSONObject;
import net.sf.json.JSONSerializer;

// v8
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
```

### API Changes

**Creating JSON Objects:**
```java
// v7
JSONObject json = new JSONObject();
json.element("key", "value");
json.accumulate("array_key", object);
json.accumulateAll(otherJson);

// v8
ObjectMapper mapper = new ObjectMapper();
ObjectNode json = mapper.createObjectNode();
json.put("key", "value");
json.set("array_key", arrayNode);
json.setAll(otherObjectNode);
```

**Parsing JSON:**
```java
// v7
JSON jsonFieldIndexes = JSONSerializer.toJSON(listIndexesFilesToRemove);
if (!jsonFieldIndexes.isArray()) { ... }
JSONArray jsonArray = (JSONArray) jsonFieldIndexes;
String value = jsonArray.getString(nIndex);

// v8
ObjectMapper mapper = new ObjectMapper();
JsonNode jsonFieldIndexes = mapper.valueToTree(listIndexesFilesToRemove);
if (!jsonFieldIndexes.isArray()) { ... }
ArrayNode jsonArray = (ArrayNode) jsonFieldIndexes;
String value = jsonArray.get(nIndex).asText();
```

**Building JSON with Arrays:**
```java
// v7
public static JSONObject getUploadedFileJSON(List<FileItem> listFileItem) {
    JSONObject json = new JSONObject();
    if (listFileItem != null) {
        for (FileItem fileItem : listFileItem) {
            JSONObject jsonObject = new JSONObject();
            jsonObject.element(JSON_KEY_FILE_NAME, fileItem.getName());
            json.accumulate(JSON_KEY_UPLOADED_FILES, jsonObject);
        }
        json.element(JSON_KEY_FILE_COUNT, listFileItem.size());
    }
    return json;
}

// v8 (Handles single vs multiple files differently)
public static ObjectNode getUploadedFileJSON(List<MultipartItem> listFileItem) {
    ObjectMapper mapper = new ObjectMapper();
    ObjectNode json = mapper.createObjectNode();

    if (listFileItem != null && !listFileItem.isEmpty()) {
        if (1 == listFileItem.size()) {
            ObjectNode jsonObject = mapper.createObjectNode();
            MultipartItem fileItem = listFileItem.get(0);
            jsonObject.put(JSON_KEY_FILE_NAME, fileItem.getName());
            json.set(JSON_KEY_UPLOADED_FILES, jsonObject);
            json.put(JSON_KEY_FILE_COUNT, 1);
        } else {
            ArrayNode uploadedFilesArray = mapper.createArrayNode();
            for (MultipartItem fileItem : listFileItem) {
                ObjectNode jsonObject = mapper.createObjectNode();
                jsonObject.put(JSON_KEY_FILE_NAME, fileItem.getName());
                uploadedFilesArray.add(jsonObject);
            }
            json.set(JSON_KEY_UPLOADED_FILES, uploadedFilesArray);
            json.put(JSON_KEY_FILE_COUNT, listFileItem.size());
        }
    } else {
        json.put(JSON_KEY_FILE_COUNT, 0);
    }
    return json;
}
```

**Building JSON Errors (Accumulating):**
```java
// v7
public static void buildJsonError(JSONObject json, String strMessage) {
    if (json != null) {
        json.accumulate(JSON_KEY_FORM_ERROR, strMessage);
    }
}

// v8 (Manual array handling)
public static void buildJsonError(ObjectNode json, String strMessage) {
    if (json != null) {
        ObjectMapper mapper = new ObjectMapper();
        JsonNode node = json.get(JSON_KEY_FORM_ERROR);
        ArrayNode arrayErrors = mapper.createArrayNode();
        if (null != node && node.isArray()) {
            for (JsonNode jsonNode : node) {
                arrayErrors.add(jsonNode);
            }
        }
        arrayErrors.add(strMessage);
        json.set(JSON_KEY_FORM_ERROR, arrayErrors);
    }
}
```

