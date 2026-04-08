# LUB-V-control

This repository is for programming the **LUB-V greaser** — an automatic lubrication device controlled via a Siemens PLC (TIA Portal / S7-1500).

## Contents

| File | Description |
|------|-------------|
| `LUB_V_protocol_documentation.md` | PLC ↔ LUB-V communication protocol reference |
| `FB_LUB_V_Greaser_V033_Original.scl.st` | Original SCL function block (contains known bugs) |
| `FB_LUB_V_Greaser_V033_Fixed.scl.st` | Bug-fixed SCL function block (recommended version) |

## Bug Fixes in V033_Fixed

1. **Edge Counting Bug** – State 30 previously counted both rising and falling edges (`<>`), causing the feedback pulse count to be doubled. Fixed to count rising edges only (`AND NOT`).
2. **Timeout Bug** – The overall response timeout (`tLubeTimeout`) was set to `t#20s`, which is shorter than the protocol's specified 30-second window. Fixed to `t#30s`.

## License

See [LICENSE](LICENSE) for details.
