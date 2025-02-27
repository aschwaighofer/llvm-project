// RUN: %clang_cc1 %s -triple spir-unknown-unknown -cl-std=clc++ -emit-llvm -pedantic -verify -O0 -o - -DDECL | FileCheck %s --check-prefixes="COMMON,EXPL"
// RUN: %clang_cc1 %s -triple spir-unknown-unknown -cl-std=clc++ -emit-llvm -pedantic -verify -O0 -o - -DDECL -DUSE_DEFLT | FileCheck %s --check-prefixes="COMMON,IMPL"
// RUN: %clang_cc1 %s -triple spir-unknown-unknown -cl-std=clc++ -emit-llvm -pedantic -verify -O0 -o - | FileCheck %s --check-prefixes="COMMON,IMPL"
// expected-no-diagnostics

// Test that the 'this' pointer is in the __generic address space.

#ifdef USE_DEFLT
#define DEFAULT =default
#else
#define DEFAULT
#endif

class C {
public:
  int v;
#ifdef DECL
  C() DEFAULT;
  C(C &&c) DEFAULT;
  C(const C &c) DEFAULT;
  C &operator=(const C &c) DEFAULT;
  C &operator=(C &&c) & DEFAULT;
#endif
  C operator+(const C& c) {
    v += c.v;
    return *this;
  }

  int get() { return v; }

  int outside();
};

#if defined(DECL) && !defined(USE_DEFLT)
C::C() { v = 2; };

C::C(C &&c) { v = c.v; }

C::C(const C &c) { v = c.v; }

C &C::operator=(const C &c) {
  v = c.v;
  return *this;
}

C &C::operator=(C &&c) & {
  v = c.v;
  return *this;
}
#endif

int C::outside() {
  return v;
}

extern C&& foo();

__global C c;

__kernel void test__global() {
  int i = c.get();
  int i2 = (&c)->get();
  int i3 = c.outside();
  C c1(c);
  C c2;
  c2 = c1;
  C c3 = c1 + c2;
  C c4(foo());
  C c5 = foo();
}

// Test that the address space is __generic for all members
// EXPL: @_ZNU3AS41CC2Ev(%class.C addrspace(4)* %this)
// EXPL: @_ZNU3AS41CC1Ev(%class.C addrspace(4)* %this)
// EXPL: @_ZNU3AS41CC2EOU3AS4S_(%class.C addrspace(4)* %this
// EXPL: @_ZNU3AS41CC1EOU3AS4S_(%class.C addrspace(4)* %this
// EXPL: @_ZNU3AS41CC2ERU3AS4KS_(%class.C addrspace(4)* %this
// EXPL: @_ZNU3AS41CC1ERU3AS4KS_(%class.C addrspace(4)* %this
// EXPL: @_ZNU3AS41CaSERU3AS4KS_(%class.C addrspace(4)* %this
// EXPL: @_ZNU3AS4R1CaSEOU3AS4S_(%class.C addrspace(4)* %this
// COMMON: @_ZNU3AS41C7outsideEv(%class.C addrspace(4)* %this)

// EXPL-LABEL: @__cxx_global_var_init()
// EXPL: call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* addrspacecast (%class.C addrspace(1)* @c to %class.C addrspace(4)*))

// COMMON-LABEL: @test__global()

// Test the address space of 'this' when invoking a method.
// COMMON: call spir_func i32 @_ZNU3AS41C3getEv(%class.C addrspace(4)* addrspacecast (%class.C addrspace(1)* @c to %class.C addrspace(4)*))
// Test the address space of 'this' when invoking a method using a pointer to the object.
// COMMON: call spir_func i32 @_ZNU3AS41C3getEv(%class.C addrspace(4)* addrspacecast (%class.C addrspace(1)* @c to %class.C addrspace(4)*))

// Test the address space of 'this' when invoking a method that is declared in the file contex.
// COMMON: call spir_func i32 @_ZNU3AS41C7outsideEv(%class.C addrspace(4)* addrspacecast (%class.C addrspace(1)* @c to %class.C addrspace(4)*))

// Test the address space of 'this' when invoking copy-constructor.
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// IMPL: [[C1VOID:%[0-9]+]] = bitcast %class.C* %c1 to i8*
// IMPL: call void @llvm.memcpy.p0i8.p4i8.i32(i8* {{.*}}[[C1VOID]], i8 addrspace(4)* {{.*}}addrspacecast (i8 addrspace(1)* bitcast (%class.C addrspace(1)* @c to i8 addrspace(1)*) to i8 addrspace(4)*)
// EXPL: call spir_func void @_ZNU3AS41CC1ERU3AS4KS_(%class.C addrspace(4)* [[C1GEN]], %class.C addrspace(4)* dereferenceable(4) addrspacecast (%class.C addrspace(1)* @c to %class.C addrspace(4)*))

// Test the address space of 'this' when invoking a constructor.
// EXPL:   [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL:   call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* [[C2GEN]])

// Test the address space of 'this' when invoking assignment operator.
// COMMON:  [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// COMMON:  [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL: call spir_func dereferenceable(4) %class.C addrspace(4)* @_ZNU3AS41CaSERU3AS4KS_(%class.C addrspace(4)* [[C2GEN]], %class.C addrspace(4)* dereferenceable(4) [[C1GEN]])
// IMPL: [[C2GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C2GEN]] to i8 addrspace(4)*
// IMPL: [[C1GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C1GEN]] to i8 addrspace(4)*
// IMPL: call void @llvm.memcpy.p4i8.p4i8.i32(i8 addrspace(4)* {{.*}}[[C2GENVOID]], i8 addrspace(4)* {{.*}}[[C1GENVOID]]

// Test the address space of 'this' when invoking the operator+
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// COMMON: [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// COMMON: call spir_func void @_ZNU3AS41CplERU3AS4KS_(%class.C* sret %c3, %class.C addrspace(4)* [[C1GEN]], %class.C addrspace(4)* dereferenceable(4) [[C2GEN]])

// Test the address space of 'this' when invoking the move constructor
// COMMON: [[C4GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c4 to %class.C addrspace(4)*
// COMMON: [[CALL:%call[0-9]+]] = call spir_func dereferenceable(4) %class.C addrspace(4)* @_Z3foov()
// EXPL: call spir_func void @_ZNU3AS41CC1EOU3AS4S_(%class.C addrspace(4)* [[C4GEN]], %class.C addrspace(4)* dereferenceable(4) [[CALL]])
// IMPL: [[C4VOID:%[0-9]+]] = bitcast %class.C* %c4 to i8*
// IMPL: [[CALLVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[CALL]] to i8 addrspace(4)*
// IMPL:  call void @llvm.memcpy.p0i8.p4i8.i32(i8* {{.*}}[[C4VOID]], i8 addrspace(4)* {{.*}}[[CALLVOID]]

// Test the address space of 'this' when invoking the move assignment
// COMMON: [[C5GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c5 to %class.C addrspace(4)*
// COMMON: [[CALL:%call[0-9]+]] = call spir_func dereferenceable(4) %class.C addrspace(4)* @_Z3foov()
// EXPL: call spir_func void @_ZNU3AS41CC1EOU3AS4S_(%class.C addrspace(4)* [[C5GEN]], %class.C addrspace(4)* dereferenceable(4) [[CALL]])
// IMPL: [[C5VOID:%[0-9]+]] = bitcast %class.C* %c5 to i8*
// IMPL: [[CALLVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[CALL]] to i8 addrspace(4)*
// IMPL: call void @llvm.memcpy.p0i8.p4i8.i32(i8* {{.*}}[[C5VOID]], i8 addrspace(4)* {{.*}}[[CALLVOID]]

// Tests address space of inline members
//COMMON: @_ZNU3AS41C3getEv(%class.C addrspace(4)* %this)
//COMMON: @_ZNU3AS41CplERU3AS4KS_(%class.C* noalias sret %agg.result, %class.C addrspace(4)* %this
#define TEST(AS)             \
  __kernel void test##AS() { \
    AS C c;                  \
    int i = c.get();         \
    C c1(c);                 \
    C c2;                    \
    c2 = c1;                 \
  }

TEST(__local)

// COMMON-LABEL: @test__local

// Test that we don't initialize an object in local address space.
// EXPL-NOT: call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* addrspacecast (%class.C addrspace(3)* @_ZZ11test__localE1c to %class.C addrspace(4)*))

// Test the address space of 'this' when invoking a method.
// COMMON: call spir_func i32 @_ZNU3AS41C3getEv(%class.C addrspace(4)* addrspacecast (%class.C addrspace(3)* @_ZZ11test__localE1c to %class.C addrspace(4)*))

// Test the address space of 'this' when invoking copy-constructor.
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// EXPL: call spir_func void @_ZNU3AS41CC1ERU3AS4KS_(%class.C addrspace(4)* [[C1GEN]], %class.C addrspace(4)* dereferenceable(4) addrspacecast (%class.C addrspace(3)* @_ZZ11test__localE1c to %class.C addrspace(4)*))
// IMPL:  [[C1VOID:%[0-9]+]] = bitcast %class.C* %c1 to i8*
// IMPL:  call void @llvm.memcpy.p0i8.p4i8.i32(i8* {{.*}}[[C1VOID]], i8 addrspace(4)* {{.*}}addrspacecast (i8 addrspace(3)* bitcast (%class.C addrspace(3)* @_ZZ11test__localE1c to i8 addrspace(3)*) to i8 addrspace(4)*), i32 4, i1 false)

// Test the address space of 'this' when invoking a constructor.
// EXPL: [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL: call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* [[C2GEN]])

// Test the address space of 'this' when invoking assignment operator.
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// COMMON: [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL: call spir_func dereferenceable(4) %class.C addrspace(4)* @_ZNU3AS41CaSERU3AS4KS_(%class.C addrspace(4)* [[C2GEN]], %class.C addrspace(4)* dereferenceable(4) [[C1GEN]])
// IMPL: [[C2GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C2GEN]] to i8 addrspace(4)*
// IMPL: [[C1GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C1GEN]] to i8 addrspace(4)*
// IMPL: call void @llvm.memcpy.p4i8.p4i8.i32(i8 addrspace(4)* {{.*}}[[C2GENVOID]], i8 addrspace(4)* {{.*}}[[C1GENVOID]]

TEST(__private)

// CHECK-LABEL: @test__private

// Test the address space of 'this' when invoking a constructor for an object in non-default address space
// EXPL: [[CGEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c to %class.C addrspace(4)*
// EXPL: call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* [[CGEN]])

// Test the address space of 'this' when invoking a method.
// COMMON: [[CGEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c to %class.C addrspace(4)*
// COMMON: call spir_func i32 @_ZNU3AS41C3getEv(%class.C addrspace(4)* [[CGEN]])

// Test the address space of 'this' when invoking a copy-constructor.
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// COMMON: [[CGEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c to %class.C addrspace(4)*
// EXPL: call spir_func void @_ZNU3AS41CC1ERU3AS4KS_(%class.C addrspace(4)* [[C1GEN]], %class.C addrspace(4)* dereferenceable(4) [[CGEN]])
// IMPL: [[C1VOID:%[0-9]+]] = bitcast %class.C* %c1 to i8*
// IMPL: [[CGENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[CGEN]] to i8 addrspace(4)*
// IMPL: call void @llvm.memcpy.p0i8.p4i8.i32(i8* {{.*}}[[C1VOID]], i8 addrspace(4)* {{.*}}[[CGENVOID]]

// Test the address space of 'this' when invoking a constructor.
// EXPL: [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL: call spir_func void @_ZNU3AS41CC1Ev(%class.C addrspace(4)* [[C2GEN]])

// Test the address space of 'this' when invoking a copy-assignment.
// COMMON: [[C1GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c1 to %class.C addrspace(4)*
// COMMON: [[C2GEN:%[.a-z0-9]+]] = addrspacecast %class.C* %c2 to %class.C addrspace(4)*
// EXPL: call spir_func dereferenceable(4) %class.C addrspace(4)* @_ZNU3AS41CaSERU3AS4KS_(%class.C addrspace(4)* [[C2GEN]], %class.C addrspace(4)* dereferenceable(4) [[C1GEN]])
// IMPL: [[C2GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C2GEN]] to i8 addrspace(4)*
// IMPL: [[C1GENVOID:%[0-9]+]] = bitcast %class.C addrspace(4)* [[C1GEN]] to i8 addrspace(4)*
// IMPL:  call void @llvm.memcpy.p4i8.p4i8.i32(i8 addrspace(4)* {{.*}}[[C2GENVOID]], i8 addrspace(4)* {{.*}}[[C1GENVOID]]

// Test that calling a const method from a non-const method does not crash Clang.
class ConstAndNonConstMethod {
public:
  void DoConst() const {
  }

  void DoNonConst() {
    DoConst();
  }
};
