use core::RangeCheck;
use core::array::ArrayTrait;
use core::byte_array::ByteArrayTrait;
use core::bytes_31::BYTES_IN_BYTES31;
use core::option::OptionTrait;
use core::serde::Serde;
use core::traits::{Into, TryInto};
#[allow(unused_imports)]
use starknet::SyscallResult;
#[allow(unused_imports)]
use starknet::class_hash::{ClassHash, ClassHashIntoFelt252, Felt252TryIntoClassHash};
#[allow(unused_imports)]
use starknet::contract_address::{
    ContractAddress, ContractAddressIntoFelt252, Felt252TryIntoContractAddress,
};
#[allow(unused_imports)]
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};

/// Represents the address of a storage value in a Starknet contract.
/// The value range of this type is `[0, 2**251)`.
#[derive(Copy, Drop)]
pub extern type StorageAddress;

#[derive(Copy, Drop)]
pub extern type StorageBaseAddress;

// Storage.
pub extern fn storage_base_address_const<const address: felt252>() -> StorageBaseAddress nopanic;
pub extern fn storage_base_address_from_felt252(
    addr: felt252,
) -> StorageBaseAddress implicits(RangeCheck) nopanic;

pub(crate) extern fn storage_address_to_felt252(address: StorageAddress) -> felt252 nopanic;
pub extern fn storage_address_from_base_and_offset(
    base: StorageBaseAddress, offset: u8,
) -> StorageAddress nopanic;

pub extern fn storage_address_from_base(base: StorageBaseAddress) -> StorageAddress nopanic;

pub(crate) extern fn storage_address_try_from_felt252(
    address: felt252,
) -> Option<StorageAddress> implicits(RangeCheck) nopanic;

impl Felt252TryIntoStorageAddress of TryInto<felt252, StorageAddress> {
    fn try_into(self: felt252) -> Option<StorageAddress> {
        storage_address_try_from_felt252(self)
    }
}
impl StorageAddressIntoFelt252 of Into<StorageAddress, felt252> {
    fn into(self: StorageAddress) -> felt252 {
        storage_address_to_felt252(self)
    }
}

impl StorageAddressSerde of Serde<StorageAddress> {
    fn serialize(self: @StorageAddress, ref output: Array<felt252>) {
        storage_address_to_felt252(*self).serialize(ref output);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<StorageAddress> {
        Option::Some(
            storage_address_try_from_felt252(Serde::<felt252>::deserialize(ref serialized)?)?,
        )
    }
}

impl StorageBaseAddressIntoFelt252 of Into<StorageBaseAddress, felt252> {
    fn into(self: StorageBaseAddress) -> felt252 {
        storage_address_to_felt252(storage_address_from_base(self))
    }
}

impl DebugStorageAddress = core::fmt::into_felt252_based::DebugImpl<StorageAddress>;
impl DebugStorageBaseAddress of core::fmt::Debug<StorageBaseAddress> {
    fn fmt(self: @StorageBaseAddress, ref f: core::fmt::Formatter) -> Result<(), core::fmt::Error> {
        DebugStorageAddress::fmt(@storage_address_from_base(*self), ref f)
    }
}

impl LowerHexStorageAddress = core::fmt::into_felt252_based::LowerHexImpl<StorageAddress>;
impl LowerHexStorageBaseAddress of core::fmt::LowerHex<StorageBaseAddress> {
    fn fmt(self: @StorageBaseAddress, ref f: core::fmt::Formatter) -> Result<(), core::fmt::Error> {
        LowerHexStorageAddress::fmt(@storage_address_from_base(*self), ref f)
    }
}

/// Trait for types that can be used as a value in Starknet storage variables.
pub trait Store<T> {
    /// Reads a value from storage from domain `address_domain` and base address `base`.
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<T>;
    /// Writes a value to storage to domain `address_domain` and base address `base`.
    fn write(address_domain: u32, base: StorageBaseAddress, value: T) -> SyscallResult<()>;
    /// Reads a value from storage from domain `address_domain` and base address `base` at offset
    /// `offset`.
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<T>;
    /// Writes a value to storage to domain `address_domain` and base address `base` at offset
    /// `offset`.
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: T,
    ) -> SyscallResult<()>;
    fn size() -> u8;
}


/// Trait for easier implementation of `Store` used for packing and unpacking values into values
/// that already implement `Store`, and having `Store` implemented using this conversion.
pub trait StorePacking<T, PackedT> {
    /// Packs a value of type `T` into a value of type `PackedT`.
    fn pack(value: T) -> PackedT;
    /// Unpacks a value of type `PackedT` into a value of type `T`.
    fn unpack(value: PackedT) -> T;
}

impl StoreUsingPacking<
    T, PackedT, impl TPacking: StorePacking<T, PackedT>, impl PackedTStore: Store<PackedT>,
> of Store<T> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<T> {
        Result::Ok(TPacking::unpack(PackedTStore::read(address_domain, base)?))
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: T) -> SyscallResult<()> {
        PackedTStore::write(address_domain, base, TPacking::pack(value))
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<T> {
        Result::Ok(TPacking::unpack(PackedTStore::read_at_offset(address_domain, base, offset)?))
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: T,
    ) -> SyscallResult<()> {
        PackedTStore::write_at_offset(address_domain, base, offset, TPacking::pack(value))
    }
    #[inline]
    fn size() -> u8 {
        PackedTStore::size()
    }
}

impl StoreFelt252 of Store<felt252> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<felt252> {
        storage_read_syscall(address_domain, storage_address_from_base(base))
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: felt252) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base(base), value)
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<felt252> {
        storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, offset))
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: felt252,
    ) -> SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset), value,
        )
    }
    #[inline]
    fn size() -> u8 {
        1_u8
    }
}

impl StorePackingBool of StorePacking<bool, felt252> {
    fn pack(value: bool) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> bool {
        value != 0
    }
}

impl StorePackingU8 of StorePacking<u8, felt252> {
    fn pack(value: u8) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> u8 {
        value.try_into().expect('StoreU8 - non u8')
    }
}

impl StorePackingI8 of StorePacking<i8, felt252> {
    fn pack(value: i8) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> i8 {
        value.try_into().expect('StoreI8 - non i8')
    }
}

impl StorePackingU16 of StorePacking<u16, felt252> {
    fn pack(value: u16) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> u16 {
        value.try_into().expect('StoreU16 - non u16')
    }
}

impl StorePackingI16 of StorePacking<i16, felt252> {
    fn pack(value: i16) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> i16 {
        value.try_into().expect('StoreI16 - non i16')
    }
}

impl StorePackingU32 of StorePacking<u32, felt252> {
    fn pack(value: u32) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> u32 {
        value.try_into().expect('StoreU32 - non u32')
    }
}

impl StorePackingI32 of StorePacking<i32, felt252> {
    fn pack(value: i32) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> i32 {
        value.try_into().expect('StoreI32 - non i32')
    }
}

impl StorePackingU64 of StorePacking<u64, felt252> {
    fn pack(value: u64) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> u64 {
        value.try_into().expect('StoreU64 - non u64')
    }
}

impl StorePackingI64 of StorePacking<i64, felt252> {
    fn pack(value: i64) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> i64 {
        value.try_into().expect('StoreI64 - non i64')
    }
}

impl StorePackingU128 of StorePacking<u128, felt252> {
    fn pack(value: u128) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> u128 {
        value.try_into().expect('StoreU128 - non u128')
    }
}

impl StorePackingI128 of StorePacking<i128, felt252> {
    fn pack(value: i128) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> i128 {
        value.try_into().expect('StoreI128 - non i128')
    }
}

impl StorePackingU256 of StorePacking<u256, (u128, u128)> {
    fn pack(value: u256) -> (u128, u128) {
        (value.low, value.high)
    }
    #[inline]
    fn unpack(value: (u128, u128)) -> u256 {
        let (low, high) = value;
        u256 { low, high }
    }
}

impl StorePackingBytes31 of StorePacking<bytes31, felt252> {
    fn pack(value: bytes31) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> bytes31 {
        value.try_into().expect('StoreBytes31 - non bytes31')
    }
}

impl StorePackingNonZero<T, +TryInto<T, NonZero<T>>> of StorePacking<NonZero<T>, T> {
    fn pack(value: NonZero<T>) -> T {
        value.into()
    }
    #[inline]
    fn unpack(value: T) -> NonZero<T> {
        value.try_into().expect('StoreNonZero - zero value')
    }
}

impl StorePackingStorageAddress of StorePacking<StorageAddress, felt252> {
    fn pack(value: StorageAddress) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> StorageAddress {
        value.try_into().expect('Non StorageAddress')
    }
}

impl StorePackingContractAddress of StorePacking<ContractAddress, felt252> {
    fn pack(value: ContractAddress) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> ContractAddress {
        value.try_into().expect('Non ContractAddress')
    }
}

impl StorePackingClassHash of StorePacking<ClassHash, felt252> {
    fn pack(value: ClassHash) -> felt252 {
        value.into()
    }
    #[inline]
    fn unpack(value: felt252) -> ClassHash {
        value.try_into().expect('Non ClassHash')
    }
}

/// Store implementation for a tuple of size 0.
impl TupleSize0Store of Store<()> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<()> {
        Result::Ok(())
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ()) -> SyscallResult<()> {
        Result::Ok(())
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<()> {
        Result::Ok(())
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: (),
    ) -> SyscallResult<()> {
        Result::Ok(())
    }
    #[inline]
    fn size() -> u8 {
        0
    }
}

/// Store packing for tuples of size 1.
impl StorePackingTuple1<T> of StorePacking<(T,), T> {
    fn pack(value: (T,)) -> T {
        let (value,) = value;
        value
    }
    fn unpack(value: T) -> (T,) {
        (value,)
    }
}

/// Store packing for small fixed sized arrays.
impl StorePackingFixedSizedArray0<T> of StorePacking<[T; 0], ()> {
    fn pack(value: [T; 0]) -> () {
        let [] = value;
        ()
    }
    #[inline]
    fn unpack(value: ()) -> [T; 0] {
        []
    }
}

/// Store packing for fixed sized arrays of size 1.
impl StorePackingFixedSizedArray1<T> of StorePacking<[T; 1], T> {
    fn pack(value: [T; 1]) -> T {
        let [value] = value;
        value
    }
    fn unpack(value: T) -> [T; 1] {
        [value]
    }
}

/// Store implementation for a tuple of size 2 and more.
impl TupleNextStore<
    T,
    impl TH: core::metaprogramming::TupleSplit<T>,
    impl HeadStore: Store<TH::Head>,
    impl RestStore: Store<TH::Rest>,
    +Drop<TH::Head>,
    +Drop<TH::Rest>,
    // The following bound is to allow the recursion to be more efficient at size 1.
    +core::metaprogramming::TupleSplit<TH::Rest>,
> of Store<T> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<T> {
        let head = HeadStore::read(address_domain, base)?;
        let rest = RestStore::read_at_offset(address_domain, base, HeadStore::size())?;
        Result::Ok(TH::reconstruct(head, rest))
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: T) -> SyscallResult<()> {
        let (head, rest) = TH::split_head(value);
        HeadStore::write(address_domain, base, head)?;
        RestStore::write_at_offset(address_domain, base, HeadStore::size(), rest)
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<T> {
        let head = HeadStore::read_at_offset(address_domain, base, offset)?;
        let rest = RestStore::read_at_offset(address_domain, base, offset + HeadStore::size())?;
        Result::Ok(TH::reconstruct(head, rest))
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: T,
    ) -> SyscallResult<()> {
        let (head, rest) = TH::split_head(value);
        HeadStore::write_at_offset(address_domain, base, offset, head)?;
        RestStore::write_at_offset(address_domain, base, offset + HeadStore::size(), rest)
    }
    #[inline]
    fn size() -> u8 {
        HeadStore::size() + RestStore::size()
    }
}

impl ResultStore<T, E, +Store<T>, +Store<E>, +Drop<T>, +Drop<E>> of Store<Result<T, E>> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Result<T, E>> {
        let idx = Store::<felt252>::read(address_domain, base)?;
        if idx == 0 {
            starknet::SyscallResult::Ok(
                Result::Ok(Store::read_at_offset(address_domain, base, 1_u8)?),
            )
        } else if idx == 1 {
            starknet::SyscallResult::Ok(
                Result::Err(Store::read_at_offset(address_domain, base, 1_u8)?),
            )
        } else {
            starknet::SyscallResult::Err(array!['Incorrect index:'])
        }
    }
    #[inline]
    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Result<T, E>,
    ) -> SyscallResult<()> {
        match value {
            Result::Ok(x) => {
                Store::write(address_domain, base, 0)?;
                Store::write_at_offset(address_domain, base, 1_u8, x)?;
            },
            Result::Err(x) => {
                Store::write(address_domain, base, 1)?;
                Store::write_at_offset(address_domain, base, 1_u8, x)?;
            },
        };
        starknet::SyscallResult::Ok(())
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<Result<T, E>> {
        let idx = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        if idx == 0 {
            starknet::SyscallResult::Ok(
                Result::Ok(Store::read_at_offset(address_domain, base, offset + 1_u8)?),
            )
        } else if idx == 1 {
            starknet::SyscallResult::Ok(
                Result::Err(Store::read_at_offset(address_domain, base, offset + 1_u8)?),
            )
        } else {
            starknet::SyscallResult::Err(array!['Incorrect index:'])
        }
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Result<T, E>,
    ) -> SyscallResult<()> {
        match value {
            Result::Ok(x) => {
                Store::write_at_offset(address_domain, base, offset, 0)?;
                Store::write_at_offset(address_domain, base, offset + 1_u8, x)?;
            },
            Result::Err(x) => {
                Store::write_at_offset(address_domain, base, offset, 0)?;
                Store::write_at_offset(address_domain, base, offset + 1_u8, x)?;
            },
        };
        starknet::SyscallResult::Ok(())
    }
    #[inline]
    fn size() -> u8 {
        1 + core::cmp::max(Store::<T>::size(), Store::<E>::size())
    }
}

impl OptionStore<T, +Store<T>, +Drop<T>> of Store<Option<T>> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Option<T>> {
        let idx = Store::<felt252>::read(address_domain, base)?;
        if idx == 1 {
            starknet::SyscallResult::Ok(
                Option::Some(Store::read_at_offset(address_domain, base, 1_u8)?),
            )
        } else if idx == 0 {
            starknet::SyscallResult::Ok(Option::None)
        } else {
            starknet::SyscallResult::Err(array!['Incorrect index:'])
        }
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Option<T>) -> SyscallResult<()> {
        match value {
            Option::Some(x) => {
                Store::write(address_domain, base, 1)?;
                Store::write_at_offset(address_domain, base, 1_u8, x)?;
            },
            Option::None(_) => { Store::write(address_domain, base, 0)?; },
        };
        starknet::SyscallResult::Ok(())
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<Option<T>> {
        let idx = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        if idx == 1 {
            starknet::SyscallResult::Ok(
                Option::Some(Store::read_at_offset(address_domain, base, offset + 1_u8)?),
            )
        } else if idx == 0 {
            starknet::SyscallResult::Ok(Option::None)
        } else {
            starknet::SyscallResult::Err(array!['Incorrect index:'])
        }
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Option<T>,
    ) -> SyscallResult<()> {
        match value {
            Option::Some(x) => {
                Store::write_at_offset(address_domain, base, offset, 1)?;
                Store::write_at_offset(address_domain, base, offset + 1_u8, x)?;
            },
            Option::None(_x) => { Store::write_at_offset(address_domain, base, offset, 0)?; },
        };
        starknet::SyscallResult::Ok(())
    }
    #[inline]
    fn size() -> u8 {
        1 + Store::<T>::size()
    }
}

/// Store for a `ByteArray`.
///
/// The layout of a `ByteArray` in storage is as follows:
/// * Only the length in bytes is stored in the original address where the byte array is logically
///   stored.
/// * The actual data is stored in chunks of 256 `bytes31`s in another place in storage
///   determined by the hash of:
///   - The address storing the length of the array.
///   - The chunk index.
///   - The short string `ByteArray`.
impl ByteArrayStore of Store<ByteArray> {
    #[inline]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ByteArray> {
        inner_read_byte_array(address_domain, storage_address_from_base(base))
    }
    #[inline]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ByteArray) -> SyscallResult<()> {
        inner_write_byte_array(address_domain, storage_address_from_base(base), value)
    }
    #[inline]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8,
    ) -> SyscallResult<ByteArray> {
        inner_read_byte_array(address_domain, storage_address_from_base_and_offset(base, offset))
    }
    #[inline]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ByteArray,
    ) -> SyscallResult<()> {
        inner_write_byte_array(
            address_domain, storage_address_from_base_and_offset(base, offset), value,
        )
    }
    #[inline]
    fn size() -> u8 {
        1
    }
}

/// Returns a pointer to the `chunk`'th chunk of the byte array at `address`.
/// The pointer is the `Poseidon` hash of:
/// * `address` - The address of the ByteArray (where the length is stored).
/// * `chunk` - The index of the chunk.
/// * The short string `ByteArray` is used as the capacity argument of the sponge construction
///   (domain separation).
fn inner_byte_array_pointer(address: StorageAddress, chunk: felt252) -> StorageBaseAddress {
    let (r, _, _) = core::poseidon::hades_permutation(address.into(), chunk, 'ByteArray'_felt252);
    storage_base_address_from_felt252(r)
}

/// Reads a byte array from storage from domain `address_domain` and address `address`.
/// The length of the byte array is read from `address` at domain `address_domain`.
/// For more info read the documentation of `ByteArrayStore`.
fn inner_read_byte_array(address_domain: u32, address: StorageAddress) -> SyscallResult<ByteArray> {
    let len: usize =
        match starknet::syscalls::storage_read_syscall(address_domain, address)?.try_into() {
        Option::Some(x) => x,
        Option::None => { return SyscallResult::Err(array!['Invalid ByteArray length']); },
    };
    let (mut remaining_full_words, pending_word_len) = core::DivRem::div_rem(
        len, BYTES_IN_BYTES31.try_into().unwrap(),
    );
    let mut chunk = 0;
    let mut chunk_base = inner_byte_array_pointer(address, chunk);
    let mut index_in_chunk = 0_u8;
    let mut result: ByteArray = Default::default();
    loop {
        if remaining_full_words == 0 {
            break Result::Ok(());
        }
        let value =
            match starknet::syscalls::storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(chunk_base, index_in_chunk),
            ) {
            Result::Ok(value) => value,
            Result::Err(err) => { break Result::Err(err); },
        };
        let value: bytes31 = match value.try_into() {
            Option::Some(x) => x,
            Option::None => { break Result::Err(array!['Invalid value']); },
        };
        result.data.append(value);
        remaining_full_words -= 1;
        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After reading 256 `bytes31`s `index_in_chunk` will overflow and we move to the
                // next chunk.
                chunk += 1;
                chunk_base = inner_byte_array_pointer(address, chunk);
                0
            },
        };
    }?;
    if pending_word_len != 0 {
        let pending_word = starknet::syscalls::storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(chunk_base, index_in_chunk),
        )?;
        result.pending_word = pending_word;
        result.pending_word_len = pending_word_len;
    }
    Result::Ok(result)
}

/// Writes a byte array to storage to domain `address_domain` and address `address`.
/// The length of the byte array is written to `address` at domain `address_domain`.
/// For more info read the documentation of `ByteArrayStore`.
fn inner_write_byte_array(
    address_domain: u32, address: StorageAddress, value: ByteArray,
) -> SyscallResult<()> {
    let len = value.len();
    starknet::syscalls::storage_write_syscall(address_domain, address, len.into())?;
    let mut full_words = value.data.span();
    let mut chunk = 0;
    let mut chunk_base = inner_byte_array_pointer(address, chunk);
    let mut index_in_chunk = 0_u8;
    loop {
        let curr_value = match full_words.pop_front() {
            Option::Some(x) => x,
            Option::None => { break Result::Ok(()); },
        };
        match starknet::syscalls::storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(chunk_base, index_in_chunk),
            (*curr_value).into(),
        ) {
            Result::Ok(_) => {},
            Result::Err(err) => { break Result::Err(err); },
        };
        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After writing 256 `byte31`s `index_in_chunk` will overflow and we move to the
                // next chunk.
                chunk += 1;
                chunk_base = inner_byte_array_pointer(address, chunk);
                0
            },
        };
    }?;
    if value.pending_word_len != 0 {
        starknet::syscalls::storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(chunk_base, index_in_chunk),
            value.pending_word,
        )?;
    }
    Result::Ok(())
}
