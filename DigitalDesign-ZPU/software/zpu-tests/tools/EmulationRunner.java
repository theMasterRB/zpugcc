/* Force the ORIGINAL Java simulator's existing software-dispatch path.
 * No opcode arithmetic/logic is implemented in this adapter.
 */
import com.zylin.zpu.simulator.Simulator;
import com.zylin.zpu.simulator.exceptions.DebuggerBreakpointException;
import com.zylin.zpu.simulator.exceptions.MemoryAccessException;
import java.io.BufferedWriter;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

class EmulationRunner {
    static class Cpu extends ReferenceRunner.Cpu {
        boolean dispatchReadPending;
        final boolean[] forced = new boolean[256];

        Cpu(long budget, BufferedWriter trace, String opcodes) throws Exception {
            super(budget, trace);
            Field field = Simulator.class.getDeclaredField("feeble");
            field.setAccessible(true);
            boolean[] feeble = (boolean[]) field.get(this);
            for (String opcode : opcodes.split(",")) {
                int number = Integer.parseInt(opcode);
                if (number < 34 || number > 63)
                    throw new IllegalArgumentException("Invalid forced opcode");
                feeble[number] = forced[number] = true;
            }
        }

        protected int readByteInternal(int address) throws MemoryAccessException {
            // Original emulate() rereads the current opcode to find its vector.
            // This is not a second executed instruction. Profiler reads already
            // bypass this method through ReferenceRunner.Cpu.readByte().
            if (dispatchReadPending) {
                dispatchReadPending = false;
                return super.readByte(address);
            }
            int opcode = super.readByteInternal(address);
            dispatchReadPending = forced[opcode];
            return opcode;
        }
    }

    public static void main(String[] args) throws Exception {
        Path imagePath = Paths.get(args[0]);
        Path directory = Paths.get(args[1]);
        long budget = Long.parseLong(args[2]);
        byte[] image = Files.readAllBytes(imagePath);
        if (image.length <= 0x2000 || image.length >= 0x4000 || budget <= 0)
            throw new IllegalArgumentException("Invalid emulation image or budget");
        Cpu cpu;
        String status;
        try (BufferedWriter trace = Files.newBufferedWriter(directory.resolve("trace.txt"))) {
            trace.write("# PC OPCODE SP TOS NOS; forced software dispatch\n");
            cpu = new Cpu(budget, trace, args[3]);
            cpu.sessionStarted();
            for (int i = 0; i < image.length; i++) cpu.writeByte(i, image[i]);
            cpu.setPc(0x2000); // Bypass boot/runtime setup, as the C++ adapter does.
            Method execute = Simulator.class.getDeclaredMethod("executeInstruction");
            execute.setAccessible(true);
            try {
                execute.invoke(cpu);
                status = "ERROR unexpected instruction-loop return";
            } catch (InvocationTargetException error) {
                Throwable cause = error.getCause();
                status = (cause instanceof DebuggerBreakpointException ? "HALT" : cpu.fault)
                       + " instructions=" + cpu.instructions
                       + " cause=" + cause.getClass().getSimpleName();
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
