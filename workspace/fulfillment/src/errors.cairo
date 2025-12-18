pub const CALLER_NOT_OWNER: felt252 = 'CALLER_NOT_OWNER';

pub fn fulfillment_exceeded_err(note: felt252) -> ByteArray {
    format!("FULFILLMENT_EXCEEDED position_id: {:?}", note)
}
