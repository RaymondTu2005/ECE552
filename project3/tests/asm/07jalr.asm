.text
main:
  #-------------------------------------------------------------
  # jalr tests (black-box, spec-level behavior only)
  #-------------------------------------------------------------

test_2: # jalr target = rs1 + imm (zero offset), rd gets the return address
  li gp, 2
  li x29, 0
  jal x5, do_jalr_2          # x5 = addr(linkpoint_2)
linkpoint_2:
  addi x29, x29, 1
  j after_2
do_jalr_2:
  jalr x1, x5, 0
  li x29, 0xdead
after_2:
  li x30, 1
  bne x29, x30, fail


test_3: # jalr target = rs1 + nonzero immediate
  li gp, 3
  li x29, 0
  jal x5, do_jalr_3          # x5 = addr(mid_3)
mid_3:
  addi x29, x0, 0             # should be skipped
linkpoint_3:
  addi x29, x29, 1
  j after_3
do_jalr_3:
  jalr x1, x5, 4               # target = x5 + 4 = addr(linkpoint_3)
  li x29, 0xdead
after_3:
  li x30, 1
  bne x29, x30, fail


test_4: # jalr must clear bit 0 of the computed target (misaligned result rounds down)
  li gp, 4
  li x29, 0
  jal x5, do_jalr_4           # x5 = addr(mid_4)
mid_4:
  addi x29, x0, 0              # should be skipped
linkpoint_4:
  addi x29, x29, 1
  j after_4
do_jalr_4:
  addi x6, x5, 5                 # x6 = addr(mid_4) + 5 (odd)
  jalr x1, x6, 0                  # raw target = x6 (odd) -> LSB cleared -> addr(mid_4) + 4 = linkpoint_4
  li x29, 0xdead
after_4:
  li x30, 1
  bne x29, x30, fail


pass:
  li a0, 1
  ebreak
fail:
  li a0, 0xdead
  ebreak
