; RUN: opt < %s -enable-coroutines -O2 -S | FileCheck --check-prefixes=CHECK %s

%async.task = type { i64 }
%async.actor = type { i64 }
%async.fp = type <{ i32, i32 }>

%async.ctxt = type { i8*, void (i8*, %async.task*, %async.actor*)* }

; The async callee.
@my_other_async_function_fp = external global <{ i32, i32 }>
declare void @my_other_async_function(i8* %async.ctxt)

; The current async function (the caller).
; This struct describes an async function. The first field is the size needed
; for the async context of the current async function, the second field is the
; relative offset to the async function implementation.
@my_async_function_fp = constant <{ i32, i32 }>
  <{ i32 128,    ; Initial async context size without space for frame
     i32 trunc ( ; Relative pointer to async function
       i64 sub (
         i64 ptrtoint (void (i8*, %async.task*, %async.actor*)* @my_async_function to i64),
         i64 ptrtoint (i32* getelementptr inbounds (<{ i32, i32 }>, <{ i32, i32 }>* @my_async_function_fp, i32 0, i32 1) to i64)
       )
     to i32)
  }>

; Function that implements the dispatch to the callee function.
define swiftcc void @my_async_function.my_other_async_function_fp.apply(i8* %async.ctxt, %async.task* %task, %async.actor* %actor) {
  musttail call swiftcc void @asyncSuspend(i8* %async.ctxt, %async.task* %task, %async.actor* %actor)
  ret void
}

define swiftcc void @my_async_function(i8* %async.ctxt, %async.task* %task, %async.actor* %actor) "coroutine.presplit"="1" {
entry:
  %id = call token @llvm.coro.id.async(i32 128, i32 16, i8* %async.ctxt, i8* bitcast (<{i32, i32}>* @my_async_function_fp to i8*))
  %hdl = call i8* @llvm.coro.begin(token %id, i8* null)

	; Begin lowering: apply %my_other_async_function(%args...)

  ; setup callee context
  %arg0 = bitcast %async.task* %task to i8*
  %arg1 = bitcast <{ i32, i32}>* @my_other_async_function_fp to i8*
  %callee_context = call i8* @llvm.coro.async.context.alloc(i8* %arg0, i8* %arg1)
	%callee_context.0 = bitcast i8* %callee_context to %async.ctxt*
  ; store arguments ...
  ; ... (omitted)

  ; store the return continuation
  %callee_context.return_to_caller.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 1
  %return_to_caller.addr = bitcast void(i8*, %async.task*, %async.actor*)** %callee_context.return_to_caller.addr to i8**
  %resume.func_ptr = call i8* @llvm.coro.async.resume()
  store i8* %resume.func_ptr, i8** %return_to_caller.addr

  ; store caller context into callee context
  %callee_context.caller_context.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 0
  store i8* %async.ctxt, i8** %callee_context.caller_context.addr

  %res = call {i8*, i8*, i8*} (i8*, i8*, ...) @llvm.coro.suspend.async(
                                                  i8* %resume.func_ptr,
                                                  i8* %callee_context,
                                                  void (i8*, %async.task*, %async.actor*)* @my_async_function.my_other_async_function_fp.apply,
                                                  i8* %callee_context, %async.task* %task, %async.actor *%actor)

  call void @llvm.coro.async.context.dealloc(i8* %callee_context)
  %continuation_task_arg = extractvalue {i8*, i8*, i8*} %res, 1
  %task.2 =  bitcast i8* %continuation_task_arg to %async.task*

  tail call swiftcc void @asyncReturn(i8* %async.ctxt, %async.task* %task.2, %async.actor* %actor)
  call i1 @llvm.coro.end(i8* %hdl, i1 0)
  unreachable
}

; CHECK: define internal swiftcc void @my_async_function.resume.0

declare token @llvm.coro.id.async(i32, i32, i8*, i8*)
declare i8* @llvm.coro.begin(token, i8*)
declare i1 @llvm.coro.end(i8*, i1)
declare {i8*, i8*, i8*} @llvm.coro.suspend.async(i8*, i8*, ...)
declare i8* @llvm.coro.async.context.alloc(i8*, i8*)
declare void @llvm.coro.async.context.dealloc(i8*)
declare swiftcc void @asyncReturn(i8*, %async.task*, %async.actor*)
declare swiftcc void @asyncSuspend(i8*, %async.task*, %async.actor*)
declare i8* @llvm.coro.async.resume()

