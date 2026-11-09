/* Adapter around the unmodified Zylin Java simulator, NOT a CPU implementation.
 * Distributed as Java 8 bytecode; execution needs only a Java 8+ runtime.
 * Pinned JAR and provenance are recorded by tools/run.py.
 */
import com.zylin.zpu.simulator.Simulator;
import com.zylin.zpu.simulator.exceptions.MemoryAccessException;
import com.zylin.zpu.simulator.exceptions.DebuggerBreakpointException;
import java.io.BufferedWriter;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.charset.StandardCharsets;

class ReferenceRunner {
    static class Cpu extends Simulator {
        final long limit;
        final BufferedWriter trace;
        long instructions = 0;
        String fault = "FAULT";

        Cpu(long limit, BufferedWriter trace) throws Exception {
            super();
            this.limit = limit;
            this.trace = trace;
        }

        protected int getRAMSIZE() { return 32768; }
        protected int getStartStack() { return 0x7ff8; }
        protected int getIO() { return 0x8000; }

        private void valid(int address, int size) throws MemoryAccessException {
            if (address < 0 || address > 32768 - size) {
                fault = address >= 0x8000 && address <= 0xffff ? "IO_ACCESS" : "FAULT";
                throw new MemoryAccessException();
            }
        }

        public int cpuReadLong(int address)
                throws com.zylin.zpu.simulator.exceptions.CPUException {
            valid(address, 4);
            return super.cpuReadLong(address);
        }

        public void cpuWriteLong(int address, int value) throws MemoryAccessException {
            valid(address, 4);
            super.cpuWriteLong(address, value);
        }

        public int readByte(int address) throws MemoryAccessException {
            // The upstream profiler calls public readByte once per instruction.
            // Those observational reads must NOT count as instruction fetches.
            valid(address, 1);
            return super.readByteInternal(address);
        }

        protected int readByteInternal(int address) throws MemoryAccessException {
            valid(address, 1);
            if (instructions >= limit) {
                fault = "TIMEOUT";
                throw new MemoryAccessException();
            }
            int opcode = super.readByteInternal(address);
            int sp = getSp();
            try {
                // One PRE-execution row for each fetched opcode, including IM
                // bytes and BREAKPOINT. Trace reads are side-effect-free RAM reads.
                int tos = sp >= 0 && sp <= 32764 ? super.cpuReadLong(sp) : 0;
                int nos = sp >= 0 && sp <= 32760 ? super.cpuReadLong(sp + 4) : 0;
                trace.write(String.format("%08x %02x %08x %08x %08x%n",
                                          address, opcode, sp, tos, nos));
            } catch (Exception error) {
                fault = "TRACE_ERROR";
                throw new MemoryAccessException();
            }
            instructions++;
            return opcode;
        }
    }

    public static void main(String[] args) throws Exception {
        Path imagePath = Paths.get(args[0]);
        Path directory = Paths.get(args[1]);
        long limit = Long.parseLong(args[2]);
        byte[] image = Files.readAllBytes(imagePath);
        if (image.length >= 0x1000 || limit <= 0)
            throw new IllegalArgumentException("Invalid image size or instruction budget");

        String status;
        Cpu cpu;
        try (BufferedWriter trace = Files.newBufferedWriter(directory.resolve("trace.txt"))) {
            trace.write("# PC OPCODE SP TOS NOS; pre-execution; one row per opcode byte\n");
            cpu = new Cpu(limit, trace);
            cpu.sessionStarted(); // allocates and clears RAM; interrupts/timer disabled
            for (int i = 0; i < image.length; i++)
                cpu.writeByte(i, image[i]);

            // The old simulator exposes a debugger-driven run loop. Calling its
            // pinned private instruction loop avoids debugger threads and lets us
            // distinguish BREAKPOINT from faults without modifying CPU semantics.
            Method execute = Simulator.class.getDeclaredMethod("executeInstruction");
            execute.setAccessible(true);
            try {
                execute.invoke(cpu);
                status = "ERROR unexpected instruction-loop return";
            } catch (InvocationTargetException error) {
                Throwable cause = error.getCause();
                if (cause instanceof DebuggerBreakpointException) {
                    status = "HALT instructions=" + cpu.instructions;
                } else {
                    status = cpu.fault + " instructions=" + cpu.instructions
                             + " cause=" + cause.getClass().getSimpleName();
                }
            }
        }
        try (BufferedWriter dump = Files.newBufferedWriter(directory.resolve("dump.hex"))) {
            for (int address = 0; address < 32768; address += 4)
                dump.write(String.format("%08x%n", cpu.cpuReadLong(address)));
        }
        Files.write(directory.resolve("status.txt"),
                    (status + "\n").getBytes(StandardCharsets.UTF_8));
        System.out.println(status);
    }
}
