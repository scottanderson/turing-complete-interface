import nimpy
import strutils, std/hashes

#{.warning[HoleEnumConv]: off.}

# The order of this enum determines the order in the component panel
type component_kind* = enum
  Error                   = 0
  Off                     = 1
  On                      = 2
  Buffer                  = 3
  Not                     = 4
  And                     = 5
  And3                    = 6
  Nand                    = 7
  Or                      = 8
  Or3                     = 9
  Nor                     = 10
  Xor                     = 11
  Xnor                    = 12
  Counter                 = 13
  VirtualCounter          = 14
  QwordCounter            = 15
  VirtualQwordCounter     = 16
  Ram                     = 17
  VirtualRam              = 18
  QwordRam                = 19
  VirtualQwordRam         = 20
  Stack                   = 21
  VirtualStack            = 22
  Register                = 23
  VirtualRegister         = 24
  RegisterRed             = 25
  VirtualRegisterRed      = 26
  RegisterRedPlus         = 27
  VirtualRegisterRedPlus  = 28
  QwordRegister           = 29
  VirtualQwordRegister    = 30
  ByteSwitch              = 31
  Mux                     = 32
  Demux                   = 33
  BiggerDemux             = 34
  ByteConstant            = 35
  ByteNot                 = 36
  ByteOr                  = 37
  ByteAnd                 = 38
  ByteXor                 = 39
  ByteEqual               = 40
  ByteLessU               = 41
  ByteLessI               = 42
  ByteNeg                 = 43
  ByteAdd2                = 44
  ByteMul2                = 45
  ByteSplitter            = 46
  ByteMaker               = 47
  QwordSplitter           = 48
  QwordMaker              = 49
  FullAdder               = 50
  BitMemory               = 51
  VirtualBitMemory        = 52
  SRLatch                 = 53
  Random                  = 54
  Clock                   = 55
  WaveformGenerator       = 56
  HttpClient              = 57
  AsciiScreen             = 58
  Keyboard                = 59
  FileInput               = 60
  Halt                    = 61
  CircuitCluster          = 62
  Screen                  = 63
  Program1                = 64
  Program1Red             = 65
  Program2                = 66
  Program3                = 67
  Program4                = 68
  LevelGate               = 69
  Input1                  = 70
  Input2                  = 71
  Input3                  = 72
  Input4                  = 73
  Input1BConditions       = 74
  Input1B                 = 75
  InputQword              = 76
  Input1BCode             = 77
  Input1_1B               = 78
  Output1                 = 79
  Output1Sum              = 80
  Output1Car              = 81
  Output1Aval             = 82
  Output1Bval             = 83
  Output2                 = 84
  Output3                 = 85
  Output4                 = 86
  Output1B                = 87
  OutputQword             = 88
  Output1_1B              = 89
  OutputCounter           = 90
  InputOutput             = 91
  Custom                  = 92
  VirtualCustom           = 93

  ByteLess                = 94
  ByteAdd                 = 95
  ByteMul                 = 96
  FlipFlop                = 97

const virtual_kinds* = [VirtualCustom, VirtualRegister, VirtualQwordRegister, VirtualBitMemory, VirtualCounter, VirtualQwordCounter, VirtualStack, VirtualRam, VirtualQwordRam, VirtualRegisterRedPlus, VirtualRegisterRed]

type circuit_kind* = enum
  ck_bit
  ck_byte
  ck_qword

proc nimpyEnumConvert*(o: component_kind): string =
  $o

proc nimpyEnumConvert*(o: circuit_kind): string =
  $o

# The main reason not to use int8 for points is that it wraps around during pathfinding
type point* = object
  x*: int16
  y*: int16

type parse_component* = object
  kind*: component_kind
  position*: point
  rotation*: uint8
  permanent_id*: uint32
  custom_string*: string
  custom_id*: int
  program_name*: string

type parse_circuit* = object
  permanent_id*: uint32
  path*: seq[point]
  kind*: circuit_kind
  color*: uint8
  comment*: string

type parse_result* = object
  components*: seq[parse_component]
  circuits*: seq[parse_circuit]
  save_version*: int
  nand*: uint32
  delay*: uint32
  custom_visible*: bool
  scale_level*: uint8
  clock_speed*: uint32
  dependencies*: seq[int]
  description*: string

proc to_string*(str: seq[uint8]): string =
  result = newStringOfCap(len(str))
  for ch in str:
    add(result, chr(ch))

proc to_bytes*(input: string): seq[uint8] =
  result = newSeq[uint8](input.len)
  for i in 0..input.high:
    result[i] = uint8(input[i])

proc file_get_bytes*(file_name: string): seq[uint8] =
  var file = open(file_name)
  defer: file.close

  let len = getFileSize(file)
  var buffer = newSeq[uint8](len)
  discard file.readBytes(buffer, 0, len)
  return buffer

# Backwards compatability November 2021
proc to_custom_id*(input: string): int =
  if input[0] in "/\\":
    return abs(hash(input[1..^1]))
  return abs(hash(input))

proc parse_state*(input: seq[uint8], meta_only: bool = false): parse_result {.exportpy.} =
  var version = input[0]
  result.nand = 99999.uint32
  result.delay = 99999.uint32
  result.clock_speed = 100.uint32
  result.custom_visible = true

  case version:
    of 48: # 0 in ascii
      if not meta_only:
        let parts = input.to_string.split("|")
        if parts.len notin [4, 5]:
          return
        if parts[1] != "":
          let component_strings = parts[1].split(";")
          for comp_string in component_strings:
            var comp_parts = comp_string.split("`")

            if comp_parts.len != 6:
              continue

            try:
              result.components.add(parse_component(
                kind: parseEnum[component_kind](comp_parts[0]),
                position: point(x: parseInt(comp_parts[1]).int16, y: parseInt(comp_parts[2]).int16),
                rotation: parseInt(comp_parts[3]).uint8,
                permanent_id: parseInt(comp_parts[4]).uint32,
                custom_string: comp_parts[5]
              ))
              if result.components[^1].kind == Custom:
                try:
                  result.components[^1].custom_id = parseInt(result.components[^1].custom_string)
                except:
                  result.components[^1].custom_id = to_custom_id(result.components[^1].custom_string) # Old school name
            except:
              discard

        var next_circuit_id = 1.uint32
        if parts[2] != "":
          let circuits_strings = parts[2].split(";")

          for circ_string in circuits_strings:
            let circ_parts = circ_string.split("`")

            if circ_parts.len != 4:
              continue

            var path = newSeq[point]()
            var x = 0.int16
            var i = 0
            if circ_parts[3] != "":
              try:
                for n in circ_parts[3].split(","):
                  if i mod 2 == 0:
                    x = parseInt(n).int16
                  else:
                    path.add(point(x: x, y: parseInt(n).int16))
                  i += 1
              except:
                continue

              result.circuits.add(parse_circuit(
                permanent_id: next_circuit_id,
                path: path,
                kind: circuit_kind(parseInt(circ_parts[0])),
                color: parseInt(circ_parts[1]).uint8,
                comment: circ_parts[2],
              ))

              next_circuit_id += 1

    of 49: # 1 in ascii
      let parts = input.to_string.split("|")
      if parts.len notin [4, 5]:
        return

      if parts[3] != "":
        try:
          var scores = parts[3].split(",")
          result.nand = parseInt(scores[0]).uint32
          result.delay = parseInt(scores[1]).uint32
        except: discard

      if parts.len == 5 and parts[4] != "":
        result.save_version = parseInt(parts[4])

      if not meta_only:
        if parts[1] != "":
          let component_strings = parts[1].split(";")
          for comp_string in component_strings:
            var comp_parts = comp_string.split("`")

            if comp_parts.len != 6:
              continue

            try:
              result.components.add(parse_component(
                kind: parseEnum[component_kind](comp_parts[0]),
                position: point(x: parseInt(comp_parts[1]).int16, y: parseInt(comp_parts[2]).int16),
                rotation: parseInt(comp_parts[3]).uint8,
                permanent_id: parseInt(comp_parts[4]).uint32,
                custom_string: comp_parts[5]
              ))
              if result.components[^1].kind == Custom:
                try:
                  result.components[^1].custom_id = parseInt(comp_parts[5])
                except:
                  result.components[^1].custom_id = to_custom_id(comp_parts[5]) # Old string name
            except:
              discard

        if parts[2] != "":
          let circuit_strings = parts[2].split(";")

          for circ_string in circuit_strings:
            let circ_parts = circ_string.split("`")

            if circ_parts.len != 5:
              continue

            var path = newSeq[point]()
            var x = 0.int16
            var i = 0
            for n in circ_parts[4].split(","):
              if i mod 2 == 0:
                x = parseInt(n).int16
              else:
                path.add(point(x: x, y: parseInt(n).int16))
              i += 1

            result.circuits.add(parse_circuit(
              permanent_id: parseInt(circ_parts[0]).uint32,
              kind: circuit_kind(parseInt(circ_parts[1])),
              color: parseInt(circ_parts[2]).uint8,
              comment: circ_parts[3],
              path: path,
            ))

    of 0:
      var i = 1 # 0th byte is version

      proc get_bool(): bool =
        result = input[i] != 0
        i += 1

      proc get_int(): int =
        result =  input[i+0].int shl 0 +
                  input[i+1].int shl 8 +
                  input[i+2].int shl 16 +
                  input[i+3].int shl 24 +
                  input[i+4].int shl 32 +
                  input[i+5].int shl 40 +
                  input[i+6].int shl 48 +
                  input[i+7].int shl 56
        i += 8

      proc get_u32(): uint32 =
        result =  input[i+0].uint32 shl 0 +
                  input[i+1].uint32 shl 8 +
                  input[i+2].uint32 shl 16 +
                  input[i+3].uint32 shl 24
        i += 4

      proc get_u16(): uint16 =
        result =  input[i+0].uint16 shl 0 +
                  input[i+1].uint16 shl 8
        i += 2

      proc get_u8(): uint8 =
        result = input[i]
        i += 1

      proc get_i8(): int8 =
        result = cast[int8](input[i])
        i += 1

      proc get_seq_i64(): seq[int] =
        let len = get_int()
        for i in 0..len - 1:
          result.add(get_int())

      proc get_string(): string =
        let len = get_int()
        for i in 0..len - 1:
          result.add(chr(get_u8()))

      proc get_point(): point =
        return point(
          x: get_i8().int16,
          y: get_i8().int16
        )

      proc get_seq_point(): seq[point] =
        let len = get_int()
        for i in 0..len - 1:
          result.add(get_point())

      proc get_component(): parse_component =
        result = parse_component(kind: component_kind(get_u16().int))
        result.position = get_point()
        result.rotation = get_u8()
        result.permanent_id = get_u32()
        result.custom_string = get_string()
        if result.kind in [Program1, Program2, Program3, Program4]:
          result.program_name = get_string()
        elif result.kind == Custom:
          result.custom_id = get_int()

      proc get_components(): seq[parse_component] =
        let len = get_int()
        for i in 0..len - 1:
          result.add(get_component())

      proc get_circuit(): parse_circuit =
        result.permanent_id = get_u32()
        result.kind = circuit_kind(get_u8())
        result.color = get_u8()
        result.comment = get_string()
        result.path = get_seq_point()

      proc get_circuits(): seq[parse_circuit] =
        let len = get_int()
        for i in 0..len - 1:
          result.add(get_circuit())

      result.save_version = get_int()
      result.nand = get_u32()
      result.delay = get_u32()
      result.custom_visible = get_bool()
      result.clock_speed = get_u32()
      result.scale_level = get_u8()
      result.dependencies = get_seq_i64()
      result.description = get_string()

      if not meta_only:
        result.components = get_components()
        result.circuits = get_circuits()

    else: discard

proc add_bytes*(arr: var seq[uint8], input: bool) =
  arr.add(input.uint8)

proc add_bytes*(arr: var seq[uint8], input: int) =
  arr.add(cast[uint8]((input shr 0)  and 0xff))
  arr.add(cast[uint8]((input shr 8)  and 0xff))
  arr.add(cast[uint8]((input shr 16) and 0xff))
  arr.add(cast[uint8]((input shr 24) and 0xff))
  arr.add(cast[uint8]((input shr 32) and 0xff))
  arr.add(cast[uint8]((input shr 40) and 0xff))
  arr.add(cast[uint8]((input shr 48) and 0xff))
  arr.add(cast[uint8]((input shr 56) and 0xff))

proc add_bytes*(arr: var seq[uint8], input: uint32) =
  arr.add(cast[uint8]((input shr 0)  and 0xff))
  arr.add(cast[uint8]((input shr 8)  and 0xff))
  arr.add(cast[uint8]((input shr 16) and 0xff))
  arr.add(cast[uint8]((input shr 24) and 0xff))

proc add_bytes*(arr: var seq[uint8], input: uint16) =
  arr.add(cast[uint8]((input shr 0)  and 0xff))
  arr.add(cast[uint8]((input shr 8)  and 0xff))

proc add_bytes*(arr: var seq[uint8], input: uint8) =
  arr.add(input)

proc add_bytes*(arr: var seq[uint8], input: component_kind) =
  arr.add_bytes(ord(input).uint16)

proc add_bytes*(arr: var seq[uint8], input: circuit_kind) =
  arr.add(ord(input).uint8)

proc add_bytes*(arr: var seq[uint8], input: point) =
  arr.add(cast[uint8](input.x.int8))
  arr.add(cast[uint8](input.y.int8))

proc add_bytes*(arr: var seq[uint8], input: seq[int]) =
  arr.add_bytes(input.len)
  for i in input:
    arr.add_bytes(i)

proc add_bytes*(arr: var seq[uint8], input: string) =
  arr.add_bytes(input.len)
  for c in input:
    arr.add_bytes(ord(c).uint8)

proc add_bytes*(arr: var seq[uint8], input: seq[point]) =
  arr.add_bytes(input.len)
  for p in input:
    arr.add_bytes(p)

proc add_bytes(arr: var seq[uint8], component: parse_component) =
  arr.add_bytes(component.kind)
  arr.add_bytes(component.position)
  arr.add_bytes(component.rotation)
  arr.add_bytes(component.permanent_id)
  arr.add_bytes(component.custom_string)
  case component.kind:
    of Program1: arr.add_bytes(component.program_name)
    of Program2: arr.add_bytes(component.program_name)
    of Program3: arr.add_bytes(component.program_name)
    of Program4: arr.add_bytes(component.program_name)
    of Custom:   arr.add_bytes(component.custom_id)
    else: discard

proc add_bytes(arr: var seq[uint8], circuit: parse_circuit) =
  arr.add_bytes(circuit.permanent_id)
  arr.add_bytes(circuit.kind)
  arr.add_bytes(circuit.color)
  arr.add_bytes(circuit.comment)
  arr.add_bytes(circuit.path)

proc state_to_binary*(save_version: int, components: seq[parse_component], circuits: seq[parse_circuit], nand: uint32, delay: uint32, custom_visible: bool, scale_level: uint8, description: string): seq[uint8] {.exportpy.} =
  var dependencies: seq[int]

  var components_to_save: seq[int]
  for id, component in components:
    if component.kind == Custom and component.custom_id notin dependencies:
      dependencies.add(component.custom_id)

    if component.kind in [CircuitCluster, VirtualCustom]: continue
    if component.kind in virtual_kinds: continue
    components_to_save.add(id)

  result.add_bytes(0.uint8) # Format version
  result.add_bytes(save_version)
  result.add_bytes(nand)
  result.add_bytes(delay)
  result.add_bytes(custom_visible)
  result.add_bytes(100.uint32) # Eventually save clock speed here, needed for sharable sandbox schematics
  result.add_bytes(scale_level)

  result.add_bytes(dependencies)

  result.add_bytes(description)

  result.add_bytes(components_to_save.len)
  for id in components_to_save:
    result.add_bytes(components[id])

  result.add_bytes(circuits.len)
  for id, circuit in circuits:
    result.add_bytes(circuit)

proc is_virtual*(component: component_kind): bool {. exportpy .} =
  return component in virtual_kinds