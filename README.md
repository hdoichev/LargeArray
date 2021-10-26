# LargeArray
# ''Usage and Desing''

## Usage
A description of this package.

## Design

LargeArray-swift.class key parts:
* Allocator-swift.class - Provides the address space where the nodes are stored. This address space is mapped to the Storage. 
* HArray-swift.class - Hierarchical array storage. Intended for fast inserting and removing of elements without having to move the other elements in the array.
* NodesPage-swift.class - Stores a set of elements. Used by the HArray to store the elements in pages rather than one at a time.
* Storage - normally a FileHandle. Used for read/write operations. The location where data is stored is determined by the Allocator.

The ``LargeArray`` stores ``Data`` objects 
