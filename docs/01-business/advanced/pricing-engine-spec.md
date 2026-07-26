# Pricing Engine Specification

The pricing engine uses integer micro-EUR arithmetic and HALF_UP rounding. It returns the price, cost estimate, margin, component trace, policy hashes, expiry, and rejection reason. Binary floating point is prohibited. Overflow, negative adjustments, caps, floors, and tax-pending behavior are explicitly tested.
