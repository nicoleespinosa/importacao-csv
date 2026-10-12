/**
 * Contexto: Testes do CsvImportController, que importa registros a partir de CSV conforme o mapeamento
 * do Custom Metadata CSVImportMapping__mdt (injetado em memória, sem depender de registros na org).
 * Histórico: 12/10/2026 - Nicole Espinosa - Criação.
 */
@IsTest
private class CsvImportControllerTest {
    private static final String CONFIGURATION = 'Contas';

    @IsTest
    static void shouldReturnColumnsByConfiguration() {
        CsvImportController.mappings = new List<CSVImportMapping__mdt>{
            newMapping(CONFIGURATION, 'Account', 'Nome', 'Name'),
            newMapping(CONFIGURATION, 'Account', 'Funcionários', 'NumberOfEmployees'),
            newMapping('Leads', 'Lead', 'Sobrenome', 'LastName')
        };

        Map<String, List<String>> result = CsvImportController.getConfigurations();

        Assert.areEqual(new List<String>{ 'Nome', 'Funcionários' }, result.get(CONFIGURATION));
        Assert.areEqual(new List<String>{ 'Sobrenome' }, result.get('Leads'));
    }

    @IsTest
    static void shouldImportValidRowsInBulkAndReturnErrors() {
        CsvImportController.mappings = new List<CSVImportMapping__mdt>{
            newMapping(CONFIGURATION, 'Account', 'Nome', 'Name'),
            newMapping(CONFIGURATION, 'Account', 'Funcionários', 'NumberOfEmployees')
        };
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            rows.add(new Map<String, String>{ 'Nome' => 'Conta ' + i, 'Funcionários' => String.valueOf(i) });
        }
        rows.add(new Map<String, String>{ 'Nome' => 'Conta inválida', 'Funcionários' => 'abc' });
        rows.add(new Map<String, String>{ 'Funcionários' => '1' });

        Test.startTest();
        Map<Integer, String> errorsByRow = CsvImportController.importRecords(CONFIGURATION, rows);
        Test.stopTest();

        Assert.areEqual(2, errorsByRow.size());
        Assert.isTrue(errorsByRow.get(200).startsWith('Funcionários: '));
        Assert.isTrue(errorsByRow.containsKey(201));
        Assert.areEqual(200, [SELECT COUNT() FROM Account]);
    }

    @IsTest
    static void shouldRejectInvalidMappings() {
        assertImportError(newMapping('Outra', 'Account', 'Nome', 'Name'), 'Configuração não encontrada: ' + CONFIGURATION);
        assertImportError(newMapping(CONFIGURATION, 'Invalido__c', 'Nome', 'Name'), 'Objeto inválido: Invalido__c');
        assertImportError(newMapping(CONFIGURATION, 'Account', 'Nome', 'Invalido__c'), 'Campo inválido: Invalido__c');
    }

    @IsTest
    static void shouldConvertValuesByFieldType() {
        Date expectedDate = Date.newInstance(2026, 10, 12);
        Datetime expectedDatetime = Datetime.newInstance(2026, 10, 12, 10, 30, 0);

        Assert.areEqual(true, CsvImportController.convert(Schema.DisplayType.BOOLEAN, 'Sim'));
        Assert.areEqual(false, CsvImportController.convert(Schema.DisplayType.BOOLEAN, 'Não'));
        Assert.areEqual(10, CsvImportController.convert(Schema.DisplayType.INTEGER, '10'));
        Assert.areEqual(1234.56, CsvImportController.convert(Schema.DisplayType.CURRENCY, '1.234,56'));
        Assert.areEqual(1234.56, CsvImportController.convert(Schema.DisplayType.DOUBLE, '1234.56'));
        Assert.areEqual(expectedDate, CsvImportController.convert(Schema.DisplayType.DATE, expectedDate.format()));
        Assert.areEqual(expectedDate, CsvImportController.convert(Schema.DisplayType.DATE, '2026-10-12'));
        Assert.areEqual(expectedDatetime, CsvImportController.convert(Schema.DisplayType.DATETIME, expectedDatetime.format()));
        Assert.areEqual(expectedDatetime, CsvImportController.convert(Schema.DisplayType.DATETIME, '2026-10-12 10:30:00'));
        Assert.areEqual('texto', CsvImportController.convert(Schema.DisplayType.STRING, 'texto'));
    }

    private static void assertImportError(CSVImportMapping__mdt mapping, String expectedMessage) {
        CsvImportController.mappings = new List<CSVImportMapping__mdt>{ mapping };
        try {
            CsvImportController.importRecords(CONFIGURATION, new List<Map<String, String>>());
            Assert.fail('Exceção esperada: ' + expectedMessage);
        } catch (AuraHandledException e) {
            Assert.areEqual(expectedMessage, e.getMessage());
        }
    }

    private static CSVImportMapping__mdt newMapping(String configuration, String objectName, String column, String field) {
        return new CSVImportMapping__mdt(
            Configuration__c = configuration,
            ObjectApiName__c = objectName,
            CsvColumn__c = column,
            FieldApiName__c = field
        );
    }
}
