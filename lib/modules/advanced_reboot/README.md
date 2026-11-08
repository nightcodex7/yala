# Advanced Reboot Subsystem for YALA

The **Advanced Reboot** subsystem provides secure, capability-based power management and dual-firmware partition switching for OpenWrt devices within YALA.

## 1. Non-Negotiable Safety Principles

1. **Zero State Changes During Detection**: Capability probing is 100% read-only. Privileged state-modifying operations such as `fw_setenv`, `sysupgrade`, or bootloader variable mutations are NEVER executed during detection.
2. **Explicit Capability States**: Capabilities are typed as `supported`, `unsupported`, `unknown`, or `error`. Missing, incomplete, or ambiguous evidence evaluates to `unknown`, NEVER `supported`.
3. **Universal Capability-Based Compatibility**: YALA supports any OpenWrt device on which a generic, documented boot mechanism can be reliably discovered, safely executed, and verified, without requiring a curated profile entry for every router model. Curated profiles exist solely for hardware quirks and vendor exceptions.
4. **Concurrency Safety**: Reboot operations acquire a router-exclusive lock (`domain: '*'`) via `RouterScopedOperationQueue`, preventing collisions with firmware upgrades, configuration restore, or concurrent reboots.
5. **Standard Reboot Independence**: Standard system reboot is always available independently of advanced boot features.

---

## 2. Layered Capability-Resolution Engine

The capability resolution engine resolves device capabilities through a strict 5-layer hierarchy:

```
┌────────────────────────────────────────────────────────┐
│ 1. Generic Documented Mechanism                        │
│    Detect standard OpenWrt boot interfaces             │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│ 2. Runtime Mechanism Discovery                         │
│    Inspect /proc/mtd, UBI, target arch & bootloader    │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│ 3. Validated Capability Adapters                       │
│    Generic typed adapters verify exact preconditions   │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│ 4. Device-Specific Profiles (Quirks / Exceptions)      │
│    Hardware-verified overrides (e.g. boot_part_ready)  │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│ 5. Unknown Fallback                                    │
│    Dual partitions present but mechanism unverified:   │
│    retains standard reboot; explains missing evidence  │
└────────────────────────────────────────────────────────┘
```

1. **Generic documented mechanism**: Identifies established interfaces (e.g. U-Boot environment variables, UBI volumes, ACPI poweroff).
2. **Runtime mechanism discovery**: Reads `/proc/mtd`, bootloader variables via `fw_printenv`, and board metadata without writing any data.
3. **Validated capability adapters**: Executes reusable, typed adapters that verify all preconditions (storage layout, active slot, target slot, utilities `fw_printenv` and `fw_setenv`).
4. **Device-specific profiles**: Exact board overrides for vendor quirks (e.g., Linksys IPQ40xx dual-variable synchronization).
5. **Unknown fallback**: When evidence is incomplete or inconclusive, safely evaluates to `unknown` and preserves standard reboot.

---

## 3. Generic Boot Mechanism Adapters

| Adapter ID | Adapter Name | Supported Operations | Verified Preconditions |
|---|---|---|---|
| `standard_reboot` | Standard OpenWrt System Reboot | `standardReboot` | LuCI `system.reboot` RPC available |
| `uboot_boot_part_ready` | U-Boot Dual-Partition with Boot Readiness | `alternatePartitionBoot` | Dual MTD partitions + `boot_part` (1/2) + `boot_part_ready` + `fw_printenv` + `fw_setenv` |
| `uboot_boot_part` | Generic U-Boot Dual-Partition (`boot_part`) | `alternatePartitionBoot` | Dual MTD partitions + `boot_part` (1/2) + `fw_printenv` + `fw_setenv` |
| `uboot_dual_image_flag` | U-Boot Dual Image Flag (`DualImageFlag`) | `alternatePartitionBoot` | Dual MTD partitions + `DualImageFlag` (0/1) + `fw_printenv` + `fw_setenv` |
| `ubi_dual_boot` | UBI Volume Dual-Boot (`active` / `boot_bank`) | `alternatePartitionBoot` | Dual UBI volume banks + `active` or `boot_bank` (0/1) + `fw_printenv` + `fw_setenv` |
| `acpi_poweroff` | ACPI / PMIC Hardware Power-Off | `powerOff` | x86_64 architecture or profile with hardware PMIC power management |

---

## 4. Subsystem Architecture

```
lib/modules/advanced_reboot/
├── advanced_reboot_module.dart       # LuciModule definition registered with LuciModuleRegistry
├── adapters/
│   ├── boot_mechanism_adapter.dart   # Reusable typed adapter contract
│   ├── boot_adapter_registry.dart    # Registry prioritizing generic and custom adapters
│   ├── standard_reboot_adapter.dart  # Native LuCI system.reboot adapter
│   ├── uboot_boot_part_adapter.dart  # Universal U-Boot boot_part (1/2) adapter
│   ├── uboot_boot_part_ready_adapter.dart # U-Boot boot_part + boot_part_ready adapter
│   ├── uboot_dual_image_flag_adapter.dart # U-Boot DualImageFlag adapter
│   ├── ubi_dual_boot_adapter.dart    # UBI active/boot_bank dual-boot adapter
│   └── acpi_poweroff_adapter.dart    # ACPI S5 poweroff adapter for x86 / PMIC platforms
├── controllers/
│   └── advanced_reboot_controller.dart # Riverpod StateNotifier managing UI lifecycle
├── models/
│   ├── reboot_capability.dart        # Typed capability models and read-only environment snapshot
│   └── reboot_state.dart             # Typed 11-state execution machine and progress model
├── profiles/
│   ├── device_profile.dart           # Immutable profile schema with fixed command generation
│   └── device_profile_registry.dart  # Curated registry of verified hardware profiles
├── screens/
│   └── advanced_reboot_screen.dart   # Material 3 UI with status chips, warnings & diagnostics sheet
└── services/
    ├── advanced_reboot_detector.dart # Read-only runtime evidence collector
    └── advanced_reboot_coordinator.dart # Exclusive lock executor with post-boot verification
```

---

## 5. Curated Hardware Exception Profiles

| Profile ID | Target Platform | Compatible Board IDs | Partition Mechanism | Verified Operations |
|---|---|---|---|---|
| `linksys_ea8300` | Qualcomm IPQ4019 (`ipq40xx/generic`) | `linksys,ea8300`, `linksys_ea8300` | U-Boot `boot_part` + `boot_part_ready` | Standard Reboot, Alternate Partition Boot |
| `linksys_wrt3200acm` | Marvell Armada 385 (`mvebu/cortexa9`) | `linksys,wrt3200acm`, `linksys_wrt3200acm` | U-Boot `boot_part` | Standard Reboot, Alternate Partition Boot |
| `linksys_wrt1900acs` | Marvell Armada 385 (`mvebu/cortexa9`) | `linksys,wrt1900acs`, `linksys_wrt1900acs` | U-Boot `boot_part` | Standard Reboot, Alternate Partition Boot |
| `generic_x86_64` | x86_64 PC / VM (`x86/64`) | `x86/64`, `generic,x86-64` | ACPI S5 State | Standard Reboot, Power Off |

---

## 6. Manual Verification Matrix for Real Hardware

> [!WARNING]
> Automated unit and widget tests mock all router operations. Real hardware partition switching should only be tested when physical access and a documented recovery method (e.g. 3-power-cycle recovery for Linksys or UART serial console) are available.

1. **Test Standard Reboot**: Safe on any router. Verifies connection drop and automated reconnection.
2. **Test Capability Detection**: Read-only. Safe on any router. Confirms MTD parsing, board detection, and sanitized diagnostics output.
3. **Test Poweroff**: Safe on x86 machines. On embedded routers, poweroff halts the CPU without cutting 12V DC input, requiring manual power cable disconnect/reconnect.
4. **Test Alternate Partition Boot**: ONLY on verified dual-boot routers (e.g. Linksys EA8300) with a known working firmware image installed in the secondary slot.
