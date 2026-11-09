/* Build-time helper, launched with a Java 11+ JDK. Not needed to run tests. */
import java.util.Arrays;
import javax.tools.JavaCompiler;
import javax.tools.StandardJavaFileManager;
import javax.tools.ToolProvider;

class CompileAdapter {
    public static void main(String[] args) throws Exception {
        JavaCompiler compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null)
            throw new IllegalStateException("A JDK is needed to rebuild the adapter");
        try (StandardJavaFileManager files = compiler.getStandardFileManager(null, null, null)) {
            java.util.List<String> options = args.length == 4
                ? Arrays.asList("-source", "8", "-target", "8", "-bootclasspath", args[3],
                                "-classpath", args[0], "-d", args[2])
                : Arrays.asList("--release", "8", "-classpath", args[0], "-d", args[2]);
            boolean ok = compiler.getTask(null, files, null,
                options,
                null, files.getJavaFileObjects(args[1])).call();
            if (!ok)
                throw new IllegalStateException("Adapter compilation failed");
        }
    }
}
