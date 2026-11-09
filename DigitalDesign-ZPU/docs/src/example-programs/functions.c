int add(int a, int b);
int mul(int a, int b);
int div (int a, int b);
double ddiv(double a, double b);

int add(int x, int y) {
    return x + y;
}

int mul(int x, int y) {
    return x * y;
}

int div(int x, int y) {
    return x / y;
}

double ddiv(double x, double y) {
    return x / y;
}


int main() {
    int num1 = 5;
    int num2 = 6;
    int sum = add(num1, num2);
    int prod = mul(num1, num2);
    int idiv = div(num1, num2);
    double d_div = ddiv(num1, num2);
    double dcast = (double) num1;
    int icast = (int) d_div;
}


