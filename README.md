# JPEG DCT Hardware Accelerator on FPGA

This project implements and evaluates a hardware acceleration flow for the Discrete Cosine Transform (DCT) stage of a JPEG-like image compression algorithm using an Intel/Altera FPGA and a Nios II soft-core processor.

The main goal of the project is to compare a pure software implementation running on Nios II with a hardware-accelerated implementation in which the computationally intensive 8×8 DCT block is offloaded to a custom Avalon-MM peripheral.

---

## Project Overview

JPEG compression is built from several stages, including:

1. Image blocking into 8×8 pixel blocks  
2. Level shifting  
3. 2D Discrete Cosine Transform  
4. Quantization  
5. Zig-zag scan  
6. Entropy/Golomb-style encoding  
7. Bitstream generation  

In this project, the focus is on accelerating the **2D DCT stage**, which is one of the most computationally expensive parts of the encoder.

The system uses:

- **Nios II processor** for software control and full encoder execution
- **Custom Verilog/SystemVerilog DCT hardware block**
- **Avalon-MM interface** for communication between software and hardware
- **JTAG UART** for debug output and bitstream export
- **Quartus Prime / Platform Designer** for FPGA system integration

---

## Hardware Platform

Tested on Intel/Altera FPGA development boards, primarily:

- DE10-Standard / Cyclone V based FPGA system
- Nios II soft-core processor
- On-chip memory and/or SDRAM
- JTAG UART for communication with the host PC

The hardware accelerator is connected to the Nios II system as a custom Avalon-MM slave peripheral.

---

## Repository Structure

```text
.
├── hardware/
│   ├── dct_accelerator.sv
│   ├── avalon_interface.sv
│   └── ...
│
├── software/
│   ├── hello_world_small.c
│   ├── jpeg_encoder.c
│   ├── image_data.h
│   └── ...
│
├── matlab/
│   ├── decoder.m
│   ├── bitstream_reader.m
│   └── ...
│
├── quartus/
│   ├── jpeg_accelerator.qsys
│   ├── jpeg_accelerator.qpf
│   └── ...
│
└── README.md
