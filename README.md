# LargeArray


## Usage

LargeArray is intended for use when large number of items, that would not fit in system memory, have to be manipulated at random locations within the array.


For example:
- creating a new LargeArray:
    let la = LargeArray(path: <some file path>, capacity: 16*1024*1024)
    ... and then use 'la' using Array semantics.
- initializing LargeArray from a file:    
    let la = LargeArray(path: <some file path>)
    ... and then use 'la' using Array semantics.
   

The objects stored in the array are persisted as JSON (binary) representatin using the Storage device. Currently only storage to file is implemented, other implementations have to provide the Storage protocol.


While accessing the array an internal cache is used to improve performance and reduce Storage access (IO operation). The cache also greatly reduces the memory usage when dealing with very large arrays.

The freed space is automatically defragmented.
