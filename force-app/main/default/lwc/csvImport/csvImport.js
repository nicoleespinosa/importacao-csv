/**
 * Contexto: Componente de importação de registros via CSV. O usuário escolhe uma configuração do Custom Metadata
 * CSVImportMapping__mdt (que define objeto e mapeamento coluna → campo), envia o arquivo e recebe o erro de cada linha.
 * Histórico: 12/10/2026 - Nicole Espinosa - Criação.
 */
import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConfigurations from '@salesforce/apex/CsvImportController.getConfigurations';
import importRecords from '@salesforce/apex/CsvImportController.importRecords';

const BATCH_SIZE = 200;
const DELIMITER = ';';
const ERROR_COLUMNS = [
    { label: 'Linha', fieldName: 'line', type: 'number', initialWidth: 90 },
    { label: 'Erro', fieldName: 'message', wrapText: true }
];

function parseCsv(text) {
    const firstLine = text.split(/\r?\n/, 1)[0];
    const delimiter = firstLine.split(';').length >= firstLine.split(',').length ? ';' : ',';
    const lines = [];
    let cells = [];
    let value = '';
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
        const char = text[i];
        if (quoted) {
            if (char === '"' && text[i + 1] === '"') {
                value += '"';
                i++;
            } else if (char === '"') {
                quoted = false;
            } else {
                value += char;
            }
        } else if (char === '"') {
            quoted = true;
        } else if (char === delimiter) {
            cells.push(value);
            value = '';
        } else if (char === '\n') {
            lines.push([...cells, value]);
            cells = [];
            value = '';
        } else if (char !== '\r') {
            value += char;
        }
    }
    lines.push([...cells, value]);
    return lines.filter((line) => line.some((cell) => cell.trim()));
}

export default class CsvImport extends LightningElement {
    errorColumns = ERROR_COLUMNS;
    columnsByConfiguration = {};
    configuration;
    fileName;
    headers = [];
    rows = [];
    errors = [];
    processed = 0;
    isLoading = false;

    @wire(getConfigurations)
    wiredConfigurations({ data, error }) {
        if (data) {
            this.columnsByConfiguration = data;
        } else if (error) {
            this.notify('error', error.body?.message);
        }
    }

    get configurationOptions() {
        return Object.keys(this.columnsByConfiguration)
            .sort()
            .map((value) => ({ label: value, value }));
    }

    get expectedColumns() {
        return this.columnsByConfiguration[this.configuration] ?? [];
    }

    get expectedColumnsLabel() {
        return this.expectedColumns.join(', ');
    }

    get progress() {
        return (this.processed / this.rows.length) * 100;
    }

    get hasErrors() {
        return this.errors.length > 0;
    }

    get isImportDisabled() {
        return !this.configuration || !this.rows.length || this.isLoading || this.processed > 0;
    }

    handleConfigurationChange(event) {
        this.configuration = event.detail.value;
        this.errors = [];
        this.processed = 0;
    }

    async handleFileChange(event) {
        const [file] = event.detail.files;
        const buffer = await file.arrayBuffer();
        let text;
        try {
            text = new TextDecoder('utf-8', { fatal: true }).decode(buffer);
        } catch {
            text = new TextDecoder('windows-1252').decode(buffer);
        }
        const [header = [], ...lines] = parseCsv(text);
        this.headers = header.map((column) => column.trim());
        this.rows = lines.map((cells) => Object.fromEntries(this.headers.map((column, i) => [column, cells[i] ?? ''])));
        this.fileName = file.name;
        this.errors = [];
        this.processed = 0;
    }

    async handleImport() {
        const missingColumns = this.expectedColumns.filter((column) => !this.headers.includes(column));
        if (missingColumns.length) {
            this.notify('error', `Colunas não encontradas no arquivo: ${missingColumns.join(', ')}`);
            return;
        }
        this.isLoading = true;
        const errors = [];
        try {
            for (let start = 0; start < this.rows.length; start += BATCH_SIZE) {
                const errorsByRow = await importRecords({
                    configuration: this.configuration,
                    rows: this.rows.slice(start, start + BATCH_SIZE)
                });
                Object.entries(errorsByRow).forEach(([index, message]) => errors.push({ line: start + Number(index) + 2, message }));
                this.processed = Math.min(start + BATCH_SIZE, this.rows.length);
            }
        } catch (error) {
            this.notify('error', error.body?.message ?? error.message);
        } finally {
            this.isLoading = false;
            this.errors = errors;
        }
        this.notify(errors.length ? 'warning' : 'success', `${this.processed - errors.length} registros importados, ${errors.length} com erro.`);
    }

    handleDownloadTemplate() {
        this.download(`modelo_${this.configuration}.csv`, [this.expectedColumns]);
    }

    handleDownloadErrors() {
        this.download(`erros_${this.configuration}.csv`, [
            [...this.headers, 'Erro'],
            ...this.errors.map(({ line, message }) => [...this.headers.map((column) => this.rows[line - 2][column]), message])
        ]);
    }

    download(fileName, lines) {
        const content = lines
            .map((cells) => cells.map((cell) => `"${String(cell ?? '').replaceAll('"', '""')}"`).join(DELIMITER))
            .join('\r\n');
        const link = document.createElement('a');
        link.href = `data:text/csv;charset=utf-8,${encodeURIComponent('﻿' + content)}`;
        link.download = fileName;
        link.click();
    }

    notify(variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Importação CSV', variant, message }));
    }
}
