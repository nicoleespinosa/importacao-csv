/**
 * Contexto: Controller do LWC csvImport. Permite importar registros de qualquer SObject a partir de um arquivo CSV,
 * usando o mapeamento coluna → campo parametrizado no Custom Metadata CSVImportMapping__mdt.
 * Histórico: 12/10/2026 - Nicole Espinosa - Criação.
 */
public with sharing class CsvImportController {
    private static final Set<String> TRUE_VALUES = new Set<String>{ 'true', '1', 'sim', 's', 'yes', 'x' };

    @TestVisible
    private static List<CSVImportMapping__mdt> mappings = CSVImportMapping__mdt.getAll().values();

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getConfigurations() {
        Map<String, List<String>> columnsByConfiguration = new Map<String, List<String>>();
        for (CSVImportMapping__mdt mapping : mappings) {
            if (!columnsByConfiguration.containsKey(mapping.Configuration__c)) {
                columnsByConfiguration.put(mapping.Configuration__c, new List<String>());
            }
            columnsByConfiguration.get(mapping.Configuration__c).add(mapping.CsvColumn__c);
        }
        return columnsByConfiguration;
    }

    @AuraEnabled
    public static Map<Integer, String> importRecords(String configuration, List<Map<String, String>> rows) {
        List<CSVImportMapping__mdt> configurationMappings = new List<CSVImportMapping__mdt>();
        for (CSVImportMapping__mdt mapping : mappings) {
            if (mapping.Configuration__c == configuration) {
                configurationMappings.add(mapping);
            }
        }
        if (configurationMappings.isEmpty()) {
            throw newError('Configuração não encontrada: ' + configuration);
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(configurationMappings[0].ObjectApiName__c);
        if (objectType == null) {
            throw newError('Objeto inválido: ' + configurationMappings[0].ObjectApiName__c);
        }

        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        Map<String, Schema.DescribeFieldResult> fieldByColumn = new Map<String, Schema.DescribeFieldResult>();
        for (CSVImportMapping__mdt mapping : configurationMappings) {
            if (!fields.containsKey(mapping.FieldApiName__c)) {
                throw newError('Campo inválido: ' + mapping.FieldApiName__c);
            }
            fieldByColumn.put(mapping.CsvColumn__c, fields.get(mapping.FieldApiName__c).getDescribe());
        }

        Map<Integer, String> errorsByRow = new Map<Integer, String>();
        List<SObject> records = new List<SObject>();
        List<Integer> recordRows = new List<Integer>();
        for (Integer i = 0; i < rows.size(); i++) {
            SObject record = objectType.newSObject();
            for (String column : fieldByColumn.keySet()) {
                Schema.DescribeFieldResult field = fieldByColumn.get(column);
                String value = rows[i].get(column)?.trim();
                try {
                    if (String.isNotBlank(value)) {
                        record.put(field.getName(), convert(field.getType(), value));
                    }
                } catch (Exception e) {
                    errorsByRow.put(i, column + ': ' + e.getMessage());
                    break;
                }
            }
            if (!errorsByRow.containsKey(i)) {
                records.add(record);
                recordRows.add(i);
            }
        }

        List<Database.SaveResult> saveResults = Database.insert(records, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (!saveResults[i].isSuccess()) {
                Database.Error error = saveResults[i].getErrors()[0];
                errorsByRow.put(recordRows[i], error.getStatusCode() + ': ' + error.getMessage());
            }
        }
        return errorsByRow;
    }

    @TestVisible
    private static Object convert(Schema.DisplayType fieldType, String value) {
        switch on fieldType {
            when BOOLEAN {
                return TRUE_VALUES.contains(value.toLowerCase());
            }
            when INTEGER {
                return Integer.valueOf(value);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(value.contains(',') ? value.remove('.').replace(',', '.') : value);
            }
            when DATE {
                return value.contains('/') ? Date.parse(value) : Date.valueOf(value);
            }
            when DATETIME {
                return value.contains('/') ? Datetime.parse(value) : Datetime.valueOf(value);
            }
            when else {
                return value;
            }
        }
    }

    private static AuraHandledException newError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
