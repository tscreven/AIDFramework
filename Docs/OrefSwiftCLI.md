# OrefSwiftCLI

The OrefSwiftCLI is a command line interface program that runs the
Swift implementation of the Oref algorithm used in Trio.

## The command line interface

The CLI supports two sets of subcommand interfaces. First, it supports
basic algorithm invocation, and the subcommands include:

  - makeProfile

  - meal

  - iob

  - autosens

  - determineBasal

Each of these basic algorithm invocations takes two command line
argument: an input file (see the `Example inputs` for more details)
and an output file, where it stores the result of the function.

Second, it can run within a simulator using these subcommands:

  - initialize: Starts a new simulator session for a given virtual
    user. Requires a `--virtual-user` (`-u`) flag with the path to a
    virtual user directory containing the user's therapy settings
    files. Automatically creates a state directory (named with the
    user name and timestamp, e.g., `state/sam_20260212_143022/`) and
    returns its path in the output for use with subsequent calls.

  - stepUpdate: Updates the state of the algorithm each simulation
    step

  - calculate: Calculates insulin dosing for a given algorithm state
    and new glucose reading

For the CLI overall, all subcommands accept inputs (-i flag) from a
given file and all subcommands output results (-o flag) to a given
file. For input flags, users can specify "-" for STDIN and for outputs
callers can specify "-" for STDOUT.

## Architecture

From an architectural perspective, we will copy files from the main
Trio repsitory into the OrefSwiftCLI directory for use in our program,
and create new files as needed. We will try to copy file without
modification but will make changes as needed to reduce dependencies
needed for our program. For example, we should exclude any
dependencies on `LoopKit` or `HealthKit` imports as the core algorithm
itself doesn't need these. However, we need to be careful to retain
all parsing logic to ensure that the JSON data we operate on converts
correctly to and from Swift objects for use by the algorithm.

Our program has three main modules:

  - OrefSwiftModels: Where we define our core data structures for
    invoking the core algorithm functions

  - OrefSwiftAlgorithm: Our core algorithm implementation

  - OrefSwiftCLI: The command line interface itself

As we copy code from the iOS implementation to the CLI implementation,
try to keep the directory and file structure the same for the two to
make it easy to navigate and easy to update if the iOS implementation
changes.

## Implementing commands

Each command follows a consistent pattern. See `MakeProfile.swift` as a
reference implementation.

### Input struct pattern

Define an input struct that represents the entire JSON input format.
The iOS codebase has reference definitions for all input types in
`@Trio/Sources/APS/OpenAPSSwift/Logging/AlgorithmComparison.swift`:

  - MakeProfileInputs
  - MealInputs
  - IobInputs
  - AutosensInputs
  - DetermineBasalInputs

### Clock field handling

The `clock` field may be either a Unix timestamp (Double) or an ISO8601
string. Handle both formats in your custom `init(from decoder:)`:

```swift
if let timestamp = try? container.decode(Double.self, forKey: .clock) {
    clock = Date(timeIntervalSince1970: timestamp)
} else if let dateString = try? container.decode(String.self, forKey: .clock) {
    if let date = Formatter.iso8601withFractionalSeconds.date(from: dateString) ??
        Formatter.iso8601.date(from: dateString)
    {
        clock = date
    } else {
        throw DecodingError.dataCorruptedError(...)
    }
}
```

### Encoding and decoding

Always use `JSONCoding.decoder` and `JSONCoding.encoder` from the
OrefSwiftModels module for consistent date handling and formatting.

## JSON parsing

When parsing JSON input, always use `JSONDecoder` directly on the raw
input data. Do NOT use `JSONSerialization.jsonObject` as an intermediate
step to extract sub-objects before decoding.

**Why**: `JSONSerialization.jsonObject` converts JSON numbers to
`NSNumber`, which internally stores them as `Double`. When these values
are re-serialized with `JSONSerialization.data`, floating-point
precision artifacts appear (e.g., `0.7` becomes `0.69999999999999996`).

**Correct approach**: Define a struct that represents the entire input
format and decode it directly:

```swift
let input = try JSONCoding.decoder.decode(MyInputStruct.self, from: inputData)
```

**Incorrect approach** (causes precision loss):

```swift
// DON'T DO THIS - precision is lost in the round-trip
let json = try JSONSerialization.jsonObject(with: inputData) as! [String: Any]
let subData = try JSONSerialization.data(withJSONObject: json["field"]!)
let value = try JSONDecoder().decode(MyType.self, from: subData)
```

## Example inputs

We have some example inputs, stored in the @OrefSwiftCLI/ExampleInputs
directory. We can use these to run through the algorithm and confirm
that it's working. For the input files, they have the following types:

  - makeProfile: MakeProfileInputs
  - meal: MealInputs
  - iob: IobInputs
  - autosens: AutosensInputs
  - determineBasal: DetermineBasalInputs

Note: Any dates are stored as timestamp numbers in the JSON input file

## Writing CLI test cases

Each algorithm function should have a corresponding `*CliTests.swift`
file in `@TrioTests/OpenAPSSwiftTests/` that verifies the iOS
implementation matches the CLI implementation. See `IobCliTests.swift`
as a reference implementation.

Note: Don't build the iOS portion. I can provide you with a script
that will build and test each function if needed and you can find the
scripts in @OrefSwiftCLI/Scripts

### Test pattern

The test flow for each function is:

  1. Get the list of input files from the test server via
     `HttpFiles.listFiles()`

  2. Download each file via `HttpFiles.downloadFile(at:)` to get an
     `AlgorithmComparison` struct

  3. Extract the function-specific inputs (e.g., `iobInput`,
     `mealInput`) and skip files that don't have the relevant inputs

  4. Run the iOS algorithm implementation to produce a result

  5. POST the result to the server via `HttpFiles.postOutput(to:output:)`

  6. Assert that the server returns HTTP 200 (match); HTTP 400 means
     the iOS and CLI outputs differ

### Use RawJSON, not JSON, for compute function return types

When writing the private `compute*` helper function that runs the iOS
algorithm, always use `RawJSON` as the return type, not `JSON`.

`returnOrThrow()` already returns `RawJSON` (a `String` containing
the serialized JSON). If the return type is declared as `JSON` (the
protocol), Swift wraps the value in an existential (`any JSON`).
Passing this existential through `JSONBridge.to()` or other encoding
functions will double-encode the result, turning a JSON array like
`[{"iob": -0.35}]` into a JSON string like `"[{\"iob\": -0.35}]"`.
The server then receives a string instead of the expected array,
causing all comparisons to fail.

**Correct**:

```swift
private func computeIob(iobInputs: IobInputs) async throws -> RawJSON {
    let (result, _) = OpenAPSSwift.iob(...)
    return try result.returnOrThrow()
}
// ...
let iob = try await computeIob(iobInputs: iobInputs)
let (responseData, httpResponse) = try await HttpFiles.postOutput(to: filePath, output: iob)
```

**Incorrect** (double-encodes the output):

```swift
private func computeIob(iobInputs: IobInputs) async throws -> JSON {
    // ...
}
// ...
let iob = try await computeIob(iobInputs: iobInputs)
// DON'T wrap in JSONBridge.to() — iob is already serialized JSON
let (responseData, httpResponse) = try await HttpFiles.postOutput(to: filePath, output: JSONBridge.to(iob))
```

## Directories and files

Some important directories and files include:

  - @OrefSwiftCLI/: The directory where we will store all of the source
    files for this project

  - @OrefSwiftCLI/README.md: A readme file that explains how to build
    and run the OrefSwiftCLI program

  - @Trio/Sources/APS/OpenAPSSwift/: The directory that holds our oref
    Swift implementation

  - @Trio/Sources/APS/OpenAPSSwift/Logging/AlgorithmComparison.swift:
    Contains the input struct definitions (MakeProfileInputs,
    MealInputs, IobInputs, AutosensInputs, DetermineBasalInputs) that
    define the expected fields for each command's JSON input

  - @TrioTests/OpenAPSSwiftTests/: The directory that holds our
    current unit tests for the oref Swift implementation. These tests
    should be useful for understanding the data structures used for
    inputs and outputs used by core algorithm invocations.