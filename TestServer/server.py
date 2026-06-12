#!/usr/bin/env python3
"""
Flask test server for verifying OrefSwiftCLI implementation.

This server serves algorithm input objects that can be used to run the algorithm
and verify outputs match between iOS and CLI implementations.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from flask import Flask, jsonify, request, abort

app = Flask(__name__)

# Global configuration
INPUT_DIR = None
CLI_PATH = None


def get_input_files():
    """Return a sorted list of input files in the configured directory."""
    if not INPUT_DIR or not os.path.isdir(INPUT_DIR):
        return []

    files = []
    for f in os.listdir(INPUT_DIR):
        file_path = os.path.join(INPUT_DIR, f)
        if os.path.isfile(file_path) and f.endswith('.json'):
            files.append(f)

    return sorted(files)


def determine_function(comparison_data):
    """
    Determine which algorithm function to run based on available inputs.

    Returns the function name (makeProfile, meal, iob, autosens, determineBasal)
    or None if no inputs are found.
    """
    if comparison_data.get('makeProfileInput'):
        return 'makeProfile'
    if comparison_data.get('mealInput'):
        return 'meal'
    if comparison_data.get('iobInput'):
        return 'iob'
    if comparison_data.get('autosensInput'):
        return 'autosens'
    if comparison_data.get('determineBasalInput'):
        return 'determineBasal'
    return None


def extract_input_for_function(comparison_data, function_name):
    """Extract the input data for the given function from the comparison data."""
    input_key = f'{function_name}Input'
    return comparison_data.get(input_key)


def run_cli(function_name, input_data):
    """
    Run the OrefSwiftCLI with the given function and input data.

    Returns the parsed JSON output from the CLI.
    """
    if not CLI_PATH or not os.path.isfile(CLI_PATH):
        raise RuntimeError(f"CLI not found at {CLI_PATH}")

    # Create a temporary file for the input
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as input_file:
        json.dump(input_data, input_file)
        input_path = input_file.name

    # Create a temporary file for the output
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as output_file:
        output_path = output_file.name

    try:
        # Run the CLI
        result = subprocess.run(
            [CLI_PATH, function_name, '-i', input_path, '-o', output_path],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            raise RuntimeError(f"CLI failed with code {result.returncode}: {result.stderr}")

        # Read the output
        with open(output_path, 'r') as f:
            return json.load(f)

    finally:
        # Clean up temporary files
        if os.path.exists(input_path):
            os.unlink(input_path)
        if os.path.exists(output_path):
            os.unlink(output_path)


def compare_outputs(ios_output, cli_output, function_name=None):
    """
    Compare iOS and CLI outputs for equality.

    Returns True if outputs match, False otherwise.
    """
    # determineBasal generates a random UUID for 'id' on each run, so ignore it
    ignore_keys = set()
    if function_name == 'determineBasal':
        ignore_keys.add('id')

    return normalize_for_comparison(ios_output, ignore_keys) == normalize_for_comparison(cli_output, ignore_keys)


def normalize_for_comparison(obj, ignore_keys=None):
    """
    Normalize an object for comparison by handling floating point precision
    and sorting keys consistently.

    Args:
        obj: The object to normalize.
        ignore_keys: Optional set of keys to exclude from dict comparisons.
    """
    if ignore_keys is None:
        ignore_keys = set()
    if isinstance(obj, dict):
        return {k: normalize_for_comparison(v, ignore_keys) for k, v in sorted(obj.items()) if k not in ignore_keys}
    elif isinstance(obj, list):
        return [normalize_for_comparison(item, ignore_keys) for item in obj]
    elif isinstance(obj, float):
        # Round to 6 decimal places for comparison to handle floating point precision
        return round(obj, 6)
    elif isinstance(obj, (int, str, bool, type(None))):
        return obj
    else:
        return obj


@app.route('/files', methods=['GET'])
def list_files():
    """Return the sorted list of all input files."""
    files = get_input_files()
    return jsonify(files)


@app.route('/files/<file_name>', methods=['GET', 'POST'])
def handle_file(file_name):
    """
    Handle requests for individual files.

    GET: Returns the unmodified input file
    POST: Compares posted output against CLI output
    """
    file_path = os.path.join(INPUT_DIR, file_name)

    if not os.path.isfile(file_path):
        abort(404, description=f"File not found: {file_name}")

    if request.method == 'GET':
        # Return the raw input file
        with open(file_path, 'r') as f:
            data = json.load(f)
        return jsonify(data)

    elif request.method == 'POST':
        # Load the input file to determine which function to run
        with open(file_path, 'r') as f:
            comparison_data = json.load(f)

        # Determine which function to run
        function_name = determine_function(comparison_data)
        if not function_name:
            abort(400, description="No algorithm inputs found in comparison data")

        # Extract the input for the function
        input_data = extract_input_for_function(comparison_data, function_name)
        if not input_data:
            abort(400, description=f"Could not extract input for function: {function_name}")

        # Get the iOS output from the request body
        ios_output = request.get_json()
        if ios_output is None:
            abort(400, description="Request body must be valid JSON")

        try:
            # Run the CLI to get the expected output
            cli_output = run_cli(function_name, input_data)
        except Exception as e:
            abort(500, description=f"CLI execution failed: {str(e)}")

        # Compare outputs
        if compare_outputs(ios_output, cli_output, function_name):
            return jsonify({
                "status": "match",
                "function": function_name
            }), 200
        else:
            return jsonify({
                "status": "mismatch",
                "function": function_name,
                "ios_output": ios_output,
                "cli_output": cli_output
            }), 400


@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": str(error.description)}), 404


@app.errorhandler(400)
def bad_request(error):
    return jsonify({"error": str(error.description)}), 400


@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": str(error.description)}), 500


def find_cli_path():
    """Find the OrefSwiftCLI executable."""
    # Look for it in common build locations
    script_dir = Path(__file__).parent.parent

    possible_paths = [
        script_dir / '.build' / 'debug' / 'oref-swift',
        script_dir / '.build' / 'release' / 'oref-swift',
        script_dir / '.build' / 'arm64-apple-macosx' / 'debug' / 'oref-swift',
        script_dir / '.build' / 'arm64-apple-macosx' / 'release' / 'oref-swift',
        script_dir / '.build' / 'x86_64-apple-macosx' / 'debug' / 'oref-swift',
        script_dir / '.build' / 'x86_64-apple-macosx' / 'release' / 'oref-swift',
    ]

    for path in possible_paths:
        if path.is_file():
            return str(path)

    return None


def main():
    global INPUT_DIR, CLI_PATH

    parser = argparse.ArgumentParser(
        description='Flask test server for OrefSwiftCLI verification'
    )
    parser.add_argument(
        'input_dir',
        help='Directory containing input files'
    )
    parser.add_argument(
        '--cli-path',
        help='Path to oref-swift CLI executable (auto-detected if not specified)'
    )
    parser.add_argument(
        '--port',
        type=int,
        default=8123,
        help='Port to run the server on (default: 8123)'
    )
    parser.add_argument(
        '--host',
        default='127.0.0.1',
        help='Host to bind to (default: 127.0.0.1)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Run in debug mode'
    )

    args = parser.parse_args()

    # Validate input directory
    INPUT_DIR = os.path.abspath(args.input_dir)
    if not os.path.isdir(INPUT_DIR):
        print(f"Error: Input directory does not exist: {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    # Find or validate CLI path
    if args.cli_path:
        CLI_PATH = os.path.abspath(args.cli_path)
    else:
        CLI_PATH = find_cli_path()

    if not CLI_PATH or not os.path.isfile(CLI_PATH):
        print(f"Error: Could not find oref-swift CLI executable", file=sys.stderr)
        print("Please build the CLI first with: swift build", file=sys.stderr)
        print("Or specify the path with --cli-path", file=sys.stderr)
        sys.exit(1)

    print(f"Input directory: {INPUT_DIR}")
    print(f"CLI path: {CLI_PATH}")
    print(f"Starting server on {args.host}:{args.port}")

    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == '__main__':
    main()
