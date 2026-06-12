# OrefSwiftCLI Test Server

A Flask server for verifying the OrefSwiftCLI implementation against iOS algorithm outputs.

## Setup

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Build the OrefSwiftCLI:
   ```bash
   cd ..
   swift build
   ```

## Usage

Run the server with the directory containing input files:

```bash
python server.py /path/to/input/files
```

### Options

- `--cli-path PATH`: Path to the oref-swift CLI executable (auto-detected if not specified)
- `--port PORT`: Port to run the server on (default: 5000)
- `--host HOST`: Host to bind to (default: 127.0.0.1)
- `--debug`: Run in debug mode

### Example

```bash
python server.py ../ExampleInputs --port 8080 --debug
```

## Endpoints

### GET /files

Returns a sorted list of all input files.

**Response:**
```json
["file1.json", "file2.json", "file3.json"]
```

### GET /files/<file_name>

Returns the contents of the specified input file.

**Response:** The raw JSON contents of the file.

### POST /files/<file_name>

Compares the posted output against the CLI-generated output for the same input.

**Request Body:** JSON output from the iOS implementation

**Response (200 - Match):**
```json
{
  "status": "match",
  "function": "makeProfile"
}
```

**Response (400 - Mismatch):**
```json
{
  "status": "mismatch",
  "function": "makeProfile",
  "ios_output": { ... },
  "cli_output": { ... }
}
```

## Input File Format

Input files should be `AlgorithmComparison` structs saved as JSON. The server determines which algorithm to run based on which input field is present:

- `makeProfileInput` → runs `makeProfile`
- `mealInput` → runs `meal`
- `iobInput` → runs `iob`
- `autosensInput` → runs `autosens`
- `determineBasalInput` → runs `determineBasal`
