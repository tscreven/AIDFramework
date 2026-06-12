# Oref CLI Server

To help test out our command line implementation of the oref
algorithm, we are going to use a server. The server will serve
algorithm input objects that the simulator can use to run the
algorithm and produce a result and verify outputs for this input. When
verifying outputs, we will confirm that the objects produced by the
algorithm in the all and from the CLI are equal.

The server's source code should be in the @OrefSwiftCLI/TestServer
directory.

Note: In our implementation we are going to ignore timezones for now
to help keep things simple.

The server is a Flask service that takes a single command line
argument: the directory where the input files are located.

## Server basics

We are expecting the basic flow to be:

  - iOS test case gets a list of files

  - iOS test case will get each specific file

  - After running the inputs on the iOS implementation, the iOS test
    case will post the output back to the input file endpoint

    - In response to this post, the server will run the command line
      implementation of the algorithm on the same input and compare
      the output against the output posted by the iOS test case

    - An exact match results in a `200` status code, a mismatched
      outputs results in a `400` status code

## Input files

The server server input files, which are saved instances of
`AlgorithmComparison` structs. There are inputs for each of the five
functions, and the client and server are both responsible for
determining which algorithm to run based on the availability of
inputs. Note: if there is an input set, there will be only one set for
each `AlgorithmComparison` struct.

## Endpoints

The server will have two endpoints: (1) a `/files` that lists all
input files and a (2) `/files/<file_name>` endpoint for interacting
with individual files. For file name, use the file name that exists in
the local file system.

The `/files` endpoint only supports GET requests, which return the
full and sorted list of input files.

The `/files/<file_name>` endpoint supports GET requests, which returns
the unmodified input file and POST requests, where the body is an
putput object encoded using JSON that is used for comparison against
the command line implementation of the algorithm. The server will need
to use the OrefSwiftCLI command line utility to get the output data to
use for comparison.
