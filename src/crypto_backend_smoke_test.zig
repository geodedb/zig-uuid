// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros
const std = @import("std");
const crypto_backend = @import("crypto_backend");

test "uuid crypto_backend seam resolves Csprng under both flag values" {
    var a: [16]u8 = undefined;
    var b: [16]u8 = undefined;
    try crypto_backend.Csprng.bytes(&a);
    try crypto_backend.Csprng.bytes(&b);
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
    crypto_backend.assertActive();
}
