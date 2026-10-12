.text
main:
  #-------------------------------------------------------------
  # Load/Store tests (black-box, spec-level behavior only)
  #-------------------------------------------------------------

test_2: # sb + lb (sign-extended) at byte offset 0
  li x1, 0x100
  li x2, 0xffffff80
  sb x2, 0(x1)
  lb x5, 0(x1)
  li x29, 0xffffff80
  li gp, 2
  bne x5, x29, fail

test_3: # lbu (zero-extended) at the same byte
  li x1, 0x100
  lbu x5, 0(x1)
  li x29, 0x00000080
  li gp, 3
  bne x5, x29, fail

test_4: # sb + lb at byte offset 1 (unaligned within word)
  li x1, 0x100
  li x2, 0x0000007f
  sb x2, 1(x1)
  lb x5, 1(x1)
  li x29, 0x0000007f
  li gp, 4
  bne x5, x29, fail

test_5: # sb + lb at byte offset 2
  li x1, 0x100
  li x2, 0xffffffc3
  sb x2, 2(x1)
  lb x5, 2(x1)
  li x29, 0xffffffc3
  li gp, 5
  bne x5, x29, fail

test_6: # sb + lb at byte offset 3
  li x1, 0x100
  li x2, 0x00000055
  sb x2, 3(x1)
  lb x5, 3(x1)
  li x29, 0x00000055
  li gp, 6
  bne x5, x29, fail

test_7: # byte-lane isolation: storing one byte must not disturb the other 3 bytes
  li x1, 0x200
  li x2, 0x11223344
  sw x2, 0(x1)
  li x6, 0x000000ff
  sb x6, 1(x1)               # overwrite only byte 1
  lw x5, 0(x1)
  li x29, 0x1122ff44          # byte 1 (bits 15:8) replaced, rest unchanged
  li gp, 7
  bne x5, x29, fail

test_8: # sh + lh (sign-extended) at half-word offset 0
  li x1, 0x104
  li x2, 0xffff8001
  sh x2, 0(x1)
  lh x5, 0(x1)
  li x29, 0xffff8001
  li gp, 8
  bne x5, x29, fail

test_9: # lhu (zero-extended) at the same half-word
  li x1, 0x104
  lhu x5, 0(x1)
  li x29, 0x00008001
  li gp, 9
  bne x5, x29, fail

test_10: # sh + lh at half-word offset 2 (upper half of a word)
  li x1, 0x104
  li x2, 0x00007ffe
  sh x2, 2(x1)
  lh x5, 2(x1)
  li x29, 0x00007ffe
  li gp, 10
  bne x5, x29, fail

test_11: # sw + lw, full word round trip
  li x1, 0x108
  li x2, 0xdeadbeef
  sw x2, 0(x1)
  lw x5, 0(x1)
  li x29, 0xdeadbeef
  li gp, 11
  bne x5, x29, fail

pass:
  li a0, 1
  ebreak
fail:
  li a0, 0xdead
  ebreak
