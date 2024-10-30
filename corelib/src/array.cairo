//! A contiguous collection of elements of the same type in memory, written
//! `Array<T>`.
//!
//! Arrays have *O*(1) indexing, *O*(1) push and *O*(1) pop
//! (from the front).
//!
//! Arrays can only be mutated by appending to the end or popping from the front.
//!
//! # Examples
//!
//! You can explicitly create an [`Array`] with [`ArrayTrait::new`]:
//!
//! ```
//! let arr: Array<usize> = ArrayTrait::new();
//! ```
//!
//! ...or by using the `array!` macro:
//!
//! ```
//! let arr: Array<usize> = array![];
//!
//! let arr: Array<usize> = array![1, 2, 3, 4, 5];
//! ```
//!
//! You can [`append`] values onto the end of an array:
//!
//! ```
//! let mut arr = array![1, 2];
//! arr.append(3);
//! ```
//!
//! Popping values from the front works like this:
//!
//! ```
//! let mut arr = array![1, 2];
//! let one = arr.pop_front(); // Returns Option::Some(1)
//! ```
//!
//! Arrays support indexing (through the [`IndexView`] trait):
//!
//! ```
//! let arr = array![1, 2, 3];
//! let three = arr[2]; // Returns a snapshot (@T)
//! ```
//!
//! Arrays can be converted to [`Span`]s for read-only access:
//!
//! ```
//! let arr = array![1, 2, 3];
//! let span = arr.span();
//! ```
//!
//! A span can be manipulated without affecting the original array:
//!
//! ```
//! let mut arr = array![1, 2, 3];
//! let mut span = arr.span();
//! span.pop_back();
//! assert!(arr == array![1, 2, 3]);
//! ```
//!
//! [`append`]: ArrayTrait::append

#[feature("deprecated-index-traits")]
use crate::traits::IndexView;

use crate::box::BoxTrait;
#[allow(unused_imports)]
use crate::gas::withdraw_gas;
#[allow(unused_imports)]
use crate::option::OptionTrait;
use crate::serde::Serde;
use crate::metaprogramming::TypeEqual;
use crate::iter::Iterator;
use crate::RangeCheck;

/// A collection of elements of the same type continuous in memory.
#[derive(Drop)]
pub extern type Array<T>;

extern fn array_new<T>() -> Array<T> nopanic;
extern fn array_append<T>(ref arr: Array<T>, value: T) nopanic;
extern fn array_pop_front<T>(ref arr: Array<T>) -> Option<Box<T>> nopanic;
extern fn array_pop_front_consume<T>(arr: Array<T>) -> Option<(Array<T>, Box<T>)> nopanic;
pub(crate) extern fn array_snapshot_pop_front<T>(ref arr: @Array<T>) -> Option<Box<@T>> nopanic;
extern fn array_snapshot_pop_back<T>(ref arr: @Array<T>) -> Option<Box<@T>> nopanic;
extern fn array_snapshot_multi_pop_front<PoppedT, impl Info: FixedSizedArrayInfo<PoppedT>>(
    ref arr: @Array<Info::Element>
) -> Option<@Box<PoppedT>> implicits(RangeCheck) nopanic;
extern fn array_snapshot_multi_pop_back<PoppedT, impl Info: FixedSizedArrayInfo<PoppedT>>(
    ref arr: @Array<Info::Element>
) -> Option<@Box<PoppedT>> implicits(RangeCheck) nopanic;
#[panic_with('Index out of bounds', array_at)]
extern fn array_get<T>(
    arr: @Array<T>, index: usize
) -> Option<Box<@T>> implicits(RangeCheck) nopanic;
extern fn array_slice<T>(
    arr: @Array<T>, start: usize, length: usize
) -> Option<@Array<T>> implicits(RangeCheck) nopanic;
extern fn array_len<T>(arr: @Array<T>) -> usize nopanic;

/// Basic trait for the `Array` type.
#[generate_trait]
pub impl ArrayImpl<T> of ArrayTrait<T> {
    /// Constructs a new, empty `Array<T>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: Array<u32> = ArrayTrait::new();
    ///
    /// let arr = ArrayTrait::<u128>::new();
    /// ```
    ///
    /// It is also possible to use the `array!` macro to create a new array.
    ///
    /// ```
    /// let arr: Array<bool> = array![];
    /// ```
    #[inline]
    fn new() -> Array<T> nopanic {
        array_new()
    }

    /// Adds a value of type `T` to the end of the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut arr: Array<u8> = array![1, 2];
    /// arr.append(3);
    /// assert!(arr == array![1, 2, 3]);
    /// ```
    #[inline]
    fn append(ref self: Array<T>, value: T) nopanic {
        array_append(ref self, value)
    }

    /// Adds a span to the end of the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut arr: Array<u8> = array![];
    /// arr.append_span(array![1, 2, 3].span());
    /// assert!(arr == array![1, 2, 3]);
    /// ```
    fn append_span<+Clone<T>, +Drop<T>>(ref self: Array<T>, mut span: Span<T>) {
        match span.pop_front() {
            Option::Some(current) => {
                self.append(current.clone());
                self.append_span(span);
            },
            Option::None => {}
        };
    }

    /// Pops a value from the front of the array.
    /// Returns `Option::Some(value)` if the array is not empty, `Option::None` otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut arr = array![2, 3, 4];
    /// assert!(arr.pop_front() == Option::Some(2));
    /// assert!(arr.pop_front() == Option::Some(3));
    /// assert!(arr.pop_front() == Option::Some(4));
    /// assert!(arr.pop_front().is_none());
    /// ```
    #[inline]
    fn pop_front(ref self: Array<T>) -> Option<T> nopanic {
        match array_pop_front(ref self) {
            Option::Some(x) => Option::Some(x.unbox()),
            Option::None => Option::None,
        }
    }

    /// Pops a value from the front of the array.
    /// Returns an option containing the remaining array and the value removed if the array is
    /// not empty, otherwise `Option::None` and drops the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr = array![2, 3, 4];
    /// assert!(arr.pop_front_consume() == Option::Some((array![3, 4], 2)));
    ///
    /// let arr: Array<u8> = array![];
    /// assert!(arr.pop_front_consume().is_none());
    /// ```
    #[inline]
    fn pop_front_consume(self: Array<T>) -> Option<(Array<T>, T)> nopanic {
        match array_pop_front_consume(self) {
            Option::Some((arr, x)) => Option::Some((arr, x.unbox())),
            Option::None => Option::None,
        }
    }

    /// Returns an option containing a box of a snapshot of the element at the given 'index'
    /// if the array contains this index, 'Option::None' otherwise.
    ///
    /// Element at index 0 is the front of the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr = array![2, 3, 4];
    /// assert!(arr.get(1).unwrap().unbox() == @3);
    /// ```
    #[inline]
    fn get(self: @Array<T>, index: usize) -> Option<Box<@T>> {
        array_get(self, index)
    }

    /// Returns a snapshot of the element at the given index.
    ///
    /// Element at index 0 is the front of the array.
    ///
    /// # Panics
    ///
    /// Panics if the index is out of bounds.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut arr: Array<usize> = array![3,4,5,6];
    /// assert!(arr.at(1) == @4);
    /// ```
    fn at(self: @Array<T>, index: usize) -> @T {
        array_at(self, index).unbox()
    }

    /// Returns the length of the array as a `usize` value.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr = array![2, 3, 4];
    /// assert!(arr.len() == 3);
    /// ```
    #[inline]
    #[must_use]
    fn len(self: @Array<T>) -> usize {
        array_len(self)
    }

    /// Returns whether the array is empty or not.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut arr = array![];
    /// assert!(arr.is_empty());
    /// arr.append(1);
    /// assert!(!arr.is_empty());
    /// ```
    #[inline]
    #[must_use]
    fn is_empty(self: @Array<T>) -> bool {
        let mut snapshot = self;
        match array_snapshot_pop_front(ref snapshot) {
            Option::Some(_) => false,
            Option::None => true,
        }
    }

    /// Returns a span of the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: Array<u8> = array![1, 2, 3];
    /// let span: Span<u8> = arr.span();
    /// ```
    #[inline]
    #[must_use]
    fn span(snapshot: @Array<T>) -> Span<T> {
        Span { snapshot }
    }
}

/// `Default` trait implementation to create a new empty array.
impl ArrayDefault<T> of Default<Array<T>> {
    /// Returns a new empty array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: Array<u8> = Default::default();
    /// ```
    #[inline]
    fn default() -> Array<T> {
        ArrayTrait::new()
    }
}

/// `IndexView` trait implementation to access an item contained in type `Array<T>` with an index of
/// type `usize`.
impl ArrayIndex<T> of IndexView<Array<T>, usize, @T> {
    /// Returns a snapshot of the element at the given index.
    /// `IndexView` needs to be explicitly imported with `use core::ops::IndexView;`
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: @Array<u8> = @array![1, 2, 3];
    /// let element: @u8 = arr.index(0);
    /// assert!(element == @1)
    /// ```
    fn index(self: @Array<T>, index: usize) -> @T {
        array_at(self, index).unbox()
    }
}

/// `Serde` trait implementation to serialize and deserialize an `Array<T>`.
impl ArraySerde<T, +Serde<T>, +Drop<T>> of Serde<Array<T>> {
    /// Serializes an `Array<T>` into an `Array<felt252>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: Array<u8> = array![1, 2, 3];
    /// let mut output: Array<felt252> = array![];
    /// arr.serialize(ref output);
    /// assert!(output == array![3, 1, 2, 3])
    /// ```
    fn serialize(self: @Array<T>, ref output: Array<felt252>) {
        self.len().serialize(ref output);
        serialize_array_helper(self.span(), ref output);
    }

    /// Deserializes a `Span<felt252>` into an `Array<T>` and returns an option of an `Array<T>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span: Span<felt252> = array![2, 0, 1].span();
    /// let arr:  Array<u8> = Serde::deserialize(ref span).unwrap();
    /// assert!(arr == array![0, 1]);
    /// ```
    fn deserialize(ref serialized: Span<felt252>) -> Option<Array<T>> {
        let length = *serialized.pop_front()?;
        let mut arr = array![];
        deserialize_array_helper(ref serialized, arr, length)
    }
}

fn serialize_array_helper<T, +Serde<T>, +Drop<T>>(mut input: Span<T>, ref output: Array<felt252>) {
    match input.pop_front() {
        Option::Some(value) => {
            value.serialize(ref output);
            serialize_array_helper(input, ref output);
        },
        Option::None => {},
    }
}

fn deserialize_array_helper<T, +Serde<T>, +Drop<T>>(
    ref serialized: Span<felt252>, mut curr_output: Array<T>, remaining: felt252
) -> Option<Array<T>> {
    if remaining == 0 {
        return Option::Some(curr_output);
    }
    curr_output.append(Serde::deserialize(ref serialized)?);
    deserialize_array_helper(ref serialized, curr_output, remaining - 1)
}

/// A span is a view into a continuous collection of the same type - such as `Array`.
/// It is a structure with a single field that holds a snapshot of an array.
/// `Span` implements the `Copy` and the `Drop` traits.
pub struct Span<T> {
    pub(crate) snapshot: @Array<T>
}

/// `Copy` trait implementation for `Span<T>`.
impl SpanCopy<T> of Copy<Span<T>>;
/// `Drop` trait implementation for `Span<T>`.
impl SpanDrop<T> of Drop<Span<T>>;

impl ArrayIntoSpan<T, +Drop<T>> of Into<Array<T>, Span<T>> {
    /// Takes an array and returns a span of that array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: Array<u8> = array![1, 2, 3];
    /// let span: Span<u8> = arr.into();
    /// ```
    fn into(self: Array<T>) -> Span<T> {
        self.span()
    }
}


impl SpanIntoArray<T, +Drop<T>, +Clone<T>> of Into<Span<T>, Array<T>> {
    /// Turns a span into an array.
    ///
    /// This needs to allocate a new memory segment for the returned array, and *O*(*n*) operations
    /// to populate the array with the content of the span.
    ///
    /// # Examples
    ///
    /// ```
    /// let input: Span<u8> = array![1, 2, 3].span();
    /// let output: Array<u8> = input.into();
    /// assert!(input == output.span());
    /// ```
    fn into(self: Span<T>) -> Array<T> {
        let mut arr = array![];
        arr.append_span(self);
        arr
    }
}

impl SpanIntoArraySnap<T> of Into<Span<T>, @Array<T>> {
    /// Takes a span and returns a snapshot of an array.
    ///
    /// # Examples
    ///
    /// ```
    /// let span: Span<u8> = array![1, 2, 3].span();
    /// let arr: @Array<u8> = span.into();
    /// ```
    fn into(self: Span<T>) -> @Array<T> {
        self.snapshot
    }
}

/// `Serde` trait implementation to serialize and deserialize a `Span<felt252>`.
impl SpanFelt252Serde of Serde<Span<felt252>> {
    /// Serializes a `Span<felt252>` into an `Array<felt252>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let span: Span<felt252> = array![1, 2, 3].span();
    /// let mut output: Array<felt252> = array![];
    /// arr.serialize(ref output);
    /// assert!(output == array![3, 1, 2, 3].span());
    /// ```
    fn serialize(self: @Span<felt252>, ref output: Array<felt252>) {
        (*self).len().serialize(ref output);
        serialize_array_helper(*self, ref output)
    }

    /// Deserializes a `Span<felt252>` into an `Span<felt252>` and returns an option of a
    /// `Span<felt252>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span: Span<felt252> = array![2, 0, 1].span();
    /// let result:  Span<felt252> = Serde::deserialize(ref span).unwrap();
    /// assert!(result == array![0, 1]);
    /// ```
    fn deserialize(ref serialized: Span<felt252>) -> Option<Span<felt252>> {
        let length: u32 = (*serialized.pop_front()?).try_into()?;
        let res = serialized.slice(0, length);
        serialized = serialized.slice(length, serialized.len() - length);
        Option::Some(res)
    }
}

/// `Serde` trait implementation to serialize and deserialize a `Span<T>`.
impl SpanSerde<T, +Serde<T>, +Drop<T>, -TypeEqual<felt252, T>> of Serde<Span<T>> {
    /// Serializes a `Span<T>` into an `Array<felt252>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let span: Span<u8> = array![1, 2, 3].span();
    /// let mut output: Array<felt252> = array![];
    /// arr.serialize(ref output);
    /// assert!(output == array![3, 1, 2, 3].span());
    /// ```
    fn serialize(self: @Span<T>, ref output: Array<felt252>) {
        (*self).len().serialize(ref output);
        serialize_array_helper(*self, ref output)
    }

    /// Deserializes a `Span<felt252>` into an `Span<T>` and returns an option of a `Span<T>`.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span: Span<felt252> = array![2, 0, 1].span();
    /// let result:  Span<u8> = Serde::deserialize(ref span).unwrap();
    /// assert!(result == array![0, 1].span());
    /// ```
    fn deserialize(ref serialized: Span<felt252>) -> Option<Span<T>> {
        let length = *serialized.pop_front()?;
        let mut arr = array_new();
        Option::Some(deserialize_array_helper(ref serialized, arr, length)?.span())
    }
}

/// Basic trait for the `Span` type.
#[generate_trait]
pub impl SpanImpl<T> of SpanTrait<T> {
    /// Pops a value from the front of the span.
    /// Returns `Option::Some(@value)` if the array is not empty, `Option::None` otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span = array![1, 2, 3].span();
    /// assert!(span.pop_front() == Option::Some(@1));
    /// ```
    #[inline]
    fn pop_front(ref self: Span<T>) -> Option<@T> {
        let mut snapshot = self.snapshot;
        let item = array_snapshot_pop_front(ref snapshot);
        self = Span { snapshot };
        match item {
            Option::Some(x) => Option::Some(x.unbox()),
            Option::None => Option::None,
        }
    }

    /// Pops a value from the back of the span.
    /// Returns `Option::Some(@value)` if the array is not empty, `Option::None` otherwise.
    ///
    /// # Examples
    /// ```
    /// let mut span = array![1, 2, 3].span();
    /// assert!(span.pop_back() == Option::Some(@3));
    /// ```
    #[inline]
    fn pop_back(ref self: Span<T>) -> Option<@T> {
        let mut snapshot = self.snapshot;
        let item = array_snapshot_pop_back(ref snapshot);
        self = Span { snapshot };
        match item {
            Option::Some(x) => Option::Some(x.unbox()),
            Option::None => Option::None,
        }
    }

    /// Pops multiple values from the front of the span.
    /// Returns an option containing a snapshot of a box that contains the values as a fixed-size
    /// array if the action completed successfully, 'Option::None' otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span = array![1, 2, 3].span();
    /// let result = *(span.multi_pop_front::<2>().unwrap());
    /// let unboxed_result = result.unbox();
    /// assert!(unboxed_result == [1, 2]);
    /// ```
    fn multi_pop_front<const SIZE: usize>(ref self: Span<T>) -> Option<@Box<[T; SIZE]>> {
        array_snapshot_multi_pop_front(ref self.snapshot)
    }

    /// Pops multiple values from the back of the span.
    /// Returns an option containing a snapshot of a box that contains the values as a fixed-size
    /// array if the action completed successfully, 'Option::None' otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let mut span = array![1, 2, 3].span();
    /// let result = *(span.multi_pop_back::<2>().unwrap());
    /// let unboxed_result = result.unbox();
    /// assert!(unboxed_result == [2, 3]);;
    /// ```
    fn multi_pop_back<const SIZE: usize>(ref self: Span<T>) -> Option<@Box<[T; SIZE]>> {
        array_snapshot_multi_pop_back(ref self.snapshot)
    }

    /// Returns an option containing a box of a snapshot of the element at the given 'index'
    /// if the span contains this index, 'Option::None' otherwise.
    ///
    /// Element at index 0 is the front of the array.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![2, 3, 4];
    /// assert!(span.get(1).unwrap().unbox() == @3);
    /// ```
    #[inline]
    fn get(self: Span<T>, index: usize) -> Option<Box<@T>> {
        array_get(self.snapshot, index)
    }

    /// Returns a snapshot of the element at the given index.
    ///
    /// Element at index 0 is the front of the array.
    ///
    /// # Panics
    ///
    /// Panics if the index is out of bounds.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![2, 3, 4].span();
    /// assert!(span.at(1) == @3);
    /// ```
    #[inline]
    fn at(self: Span<T>, index: usize) -> @T {
        array_at(self.snapshot, index).unbox()
    }

    /// Returns a span containing values from the 'start' index, with
    /// amount equal to 'length'.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![1, 2, 3].span();
    /// assert!(span.slice(1, 2) == array![2, 3].span());
    /// ```
    #[inline]
    fn slice(self: Span<T>, start: usize, length: usize) -> Span<T> {
        Span { snapshot: array_slice(self.snapshot, start, length).expect('Index out of bounds') }
    }

    /// Returns the length of the span as a `usize` value.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![2, 3, 4].span();
    /// assert!(span.len() == 3);
    /// ```
    #[inline]
    #[must_use]
    fn len(self: Span<T>) -> usize {
        array_len(self.snapshot)
    }

    /// Returns whether the span is empty or not.
    ///
    /// # Examples
    ///
    /// ```
    /// let span: Span<felt252> = array![].span();
    /// assert!(span.is_empty());
    /// let span = array![1, 2, 3].span();
    /// assert!(!span.is_empty());
    /// ```
    #[inline]
    #[must_use]
    fn is_empty(self: Span<T>) -> bool {
        let mut snapshot = self.snapshot;
        match array_snapshot_pop_front(ref snapshot) {
            Option::Some(_) => false,
            Option::None => true,
        }
    }
}

/// `IndexView` trait implementation to access an item contained in type `Span<T>` with an index of
/// type `usize`.
pub impl SpanIndex<T> of IndexView<Span<T>, usize, @T> {
    /// Returns a snapshot of the element at the given index.
    /// `IndexView` needs to be explicitly imported with `use core::ops::IndexView;`
    ///
    /// # Examples
    ///
    /// ```
    /// let span: @Span<u8> = @array![1, 2, 3].span();
    /// let element: @u8 = span.index(0);
    /// assert!(element == @1);
    /// ```
    #[inline]
    fn index(self: @Span<T>, index: usize) -> @T {
        array_at(*self.snapshot, index).unbox()
    }
}

/// `ToSpanTrait` is a trait that, given a data structure, returns a span of the data.
pub trait ToSpanTrait<C, T> {
    /// Returns a span pointing to the data in the input.
    #[must_use]
    fn span(self: @C) -> Span<T>;
}

/// `ToSpanTrait` implementation for `Array<T>`.
impl ArrayToSpan<T> of ToSpanTrait<Array<T>, T> {
    /// Returns a `Span<T>` corresponding to a view into an `Array<T>`.
    #[inline]
    fn span(self: @Array<T>) -> Span<T> {
        ArrayTrait::span(self)
    }
}

impl SnapIntoSpanWhereToSpanTrait<C, T, +ToSpanTrait<C, T>> of Into<@C, Span<T>> {
    /// Returns a `Span<T>` corresponding to a view into the given data structure.
    fn into(self: @C) -> Span<T> {
        self.span()
    }
}

extern fn span_from_tuple<T, impl Info: FixedSizedArrayInfo<T>>(
    struct_like: Box<@T>
) -> @Array<Info::Element> nopanic;

/// `ToSpanTrait` implementation for a box containing a snapshot of a fixed-size array.
impl FixedSizeArrayBoxToSpan<T, const SIZE: usize> of ToSpanTrait<Box<@[T; SIZE]>, T> {
    /// Returns a `Span<T>` corresponding to a view into the given fixed-size array.
    ///
    /// # Examples
    ///
    /// ```
    /// let boxed_arr: Box<@[u32; 3]> = BoxTrait::new(@[1, 2, 3]);
    /// let span: Span<u32> = (@boxed_arr).span();
    /// ```
    fn span(self: @Box<@[T; SIZE]>) -> Span<T> {
        Span { snapshot: span_from_tuple(*self) }
    }
}

/// `ToSpanTrait` implementation for a snapshot of a fixed-size array.
impl FixedSizeArrayToSpan<
    T, const SIZE: usize, -TypeEqual<[T; SIZE], [T; 0]>
> of ToSpanTrait<[T; SIZE], T> {
    /// Returns a `Span<T>` corresponding to a view into the given fixed-size array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: [u32; 3] = [1, 2, 3];
    /// let span: Span<u32> = (@arr).span();
    /// ```
    #[inline]
    fn span(self: @[T; SIZE]) -> Span<T> {
        BoxTrait::new(self).span()
    }
}

/// `ToSpanTrait` implementation for a snapshot of an empty fixed-size array.
impl EmptyFixedSizeArrayImpl<T, +Drop<T>> of ToSpanTrait<[T; 0], T> {
    /// Returns a `Span<T>` corresponding to a view into the given empty fixed-size array.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr: [u32; 0] = [];
    /// let span: Span<u32> = (@arr).span();
    /// ```
    #[inline]
    fn span(self: @[T; 0]) -> Span<T> {
        array![].span()
    }
}

extern fn tuple_from_span<T, impl Info: FixedSizedArrayInfo<T>>(
    span: @Array<Info::Element>
) -> Option<@Box<T>> nopanic;

/// `TryInto` implementation from a span to fixed-size array.
impl SpanTryIntoFixedSizedArray<
    T, const SIZE: usize, -TypeEqual<[T; SIZE], [T; 0]>
> of TryInto<Span<T>, @Box<[T; SIZE]>> {
    /// Returns an option of a snapshot of a box that contains a fixed-size array.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![1, 2, 3].span();
    /// let result: Option<@Box<[felt252; 3]>> = span.try_into();
    /// ```
    #[inline]
    fn try_into(self: Span<T>) -> Option<@Box<[T; SIZE]>> {
        tuple_from_span(self.snapshot)
    }
}

/// `TryInto` implementation from a span to an empty fixed-size array.
impl SpanTryIntoEmptyFixedSizedArray<T, +Drop<T>> of TryInto<Span<T>, @Box<[T; 0]>> {
    /// Returns an option of a snapshot of a box that contains an empty fixed-size array if the span
    /// is empty, and `Option::None` otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let span = array![].span();
    /// let result: Option<@Box<[felt252; 0]>> = span.try_into();
    /// ```
    #[inline]
    fn try_into(self: Span<T>) -> Option<@Box<[T; 0]>> {
        if self.is_empty() {
            Option::Some(@BoxTrait::new([]))
        } else {
            Option::None
        }
    }
}

// TODO(spapini): Remove TDrop. It is necessary to get rid of response in case of panic.
impl ArrayTCloneImpl<T, +Clone<T>, +Drop<T>> of Clone<Array<T>> {
    /// Returns a clone of `self`.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr = array![1, 2, 3];
    /// let arr_clone = arr.clone();
    /// ```
    fn clone(self: @Array<T>) -> Array<T> {
        let mut response = array_new();
        let mut span = self.span();
        loop {
            match span.pop_front() {
                Option::Some(v) => { response.append(v.clone()); },
                Option::None => { break (); },
            };
        };
        response
    }
}

impl ArrayPartialEq<T, +PartialEq<T>> of PartialEq<Array<T>> {
    /// Returns `true` if the two arrays contain the same elements, false otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let arr_1 = array![1, 2, 3];
    /// let arr_2 = array![1, 2, 3];
    /// assert!(PartialEq::eq(@arr_1, @arr_2));
    /// ```
    fn eq(lhs: @Array<T>, rhs: @Array<T>) -> bool {
        lhs.span() == rhs.span()
    }
}

impl SpanPartialEq<T, +PartialEq<T>> of PartialEq<Span<T>> {
    /// Returns `true` if the two spans contain the same elements, false otherwise.
    ///
    /// # Examples
    ///
    /// ```
    /// let span_1 = array![1, 2, 3].span();
    /// let span_2 = array![1, 2, 3].span();
    /// assert!(PartialEq::eq(@span_1, @span_2));
    /// ```
    fn eq(lhs: @Span<T>, rhs: @Span<T>) -> bool {
        if (*lhs).len() != (*rhs).len() {
            return false;
        }
        let mut lhs_span = *lhs;
        let mut rhs_span = *rhs;
        loop {
            match lhs_span.pop_front() {
                Option::Some(lhs_v) => {
                    if lhs_v != rhs_span.pop_front().unwrap() {
                        break false;
                    }
                },
                Option::None => { break true; },
            };
        }
    }
}

/// An iterator struct over a span collection.
pub struct SpanIter<T> {
    span: Span<T>,
}

/// `Drop` trait implementation for `SpanIter<T>` struct.
impl SpanIterDrop<T> of Drop<SpanIter<T>>;
/// `Copy` trait implementation for `SpanIter<T>` struct.
impl SpanIterCopy<T> of Copy<SpanIter<T>>;

/// `Iterator` trait implementation for `SpanIter<T>` struct.
impl SpanIterator<T> of Iterator<SpanIter<T>> {
    /// Type of the elements contained in the span.
    type Item = @T;
    /// Returns an option of a snapshot of a span element if it exist, and `Option::None` otherwise.
    fn next(ref self: SpanIter<T>) -> Option<@T> {
        self.span.pop_front()
    }
}

/// `IntoIterator` trait implementation for `Span<T>`.
impl SpanIntoIterator<T> of crate::iter::IntoIterator<Span<T>> {
    type IntoIter = SpanIter<T>;
    /// Returns a `SpanIter<T>` given a `Span<T>`.
    fn into_iter(self: Span<T>) -> SpanIter<T> {
        SpanIter { span: self }
    }
}

/// An iterator struct over an array collection.
#[derive(Drop)]
pub struct ArrayIter<T> {
    array: Array<T>,
}

/// `Clone` trait implementation for `ArrayIter<T>` struct.
impl ArrayIterClone<T, +crate::clone::Clone<T>, +Drop<T>> of crate::clone::Clone<ArrayIter<T>> {
    /// Returns a clone of `self`.
    fn clone(self: @ArrayIter<T>) -> ArrayIter<T> {
        ArrayIter { array: crate::clone::Clone::clone(self.array), }
    }
}

/// `Iterator` trait implementation for `ArrayIter<T>` struct.
impl ArrayIterator<T> of Iterator<ArrayIter<T>> {
    /// Type of the elements contained in the array.
    type Item = T;
    /// Returns an option of an element of the array if it exists, and `Option::None` otherwise.
    fn next(ref self: ArrayIter<T>) -> Option<T> {
        self.array.pop_front()
    }
}

/// `IntoIterator` trait implementation for `Array<T>`.
impl ArrayIntoIterator<T> of crate::iter::IntoIterator<Array<T>> {
    type IntoIter = ArrayIter<T>;
    /// Returns an `ArrayIter<T>` given an `Array<T>`.
    fn into_iter(self: Array<T>) -> ArrayIter<T> {
        ArrayIter { array: self }
    }
}

/// Information about a fixed-sized array.
trait FixedSizedArrayInfo<S> {
    /// The type of the elements in the array.
    type Element;
    /// The size of the array.
    const SIZE: usize;
}

/// `FixedSizedArrayInfo` implementation for a fixed-size array of size `SIZE`,
/// containing elements of type `T`.
impl FixedSizedArrayInfoImpl<T, const SIZE: usize> of FixedSizedArrayInfo<[T; SIZE]> {
    type Element = T;
    const SIZE: usize = SIZE;
}
