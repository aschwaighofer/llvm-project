; RUN: opt < %s -enable-coroutines -O2 -S | FileCheck --check-prefixes=CHECK %s

%async.task = type { i64 }
%async.actor = type { i64 }
%async.fp = type <{ i32, i32 }>
%async.ctxt = type { i8*, void (i8*, %async.task*, %async.actor*)* }

@my_other_async_function_fp = external global <{ i32, i32 }>
declare void @my_other_async_function(i8* %async.ctxt)

@my_async_function_fp = constant <{ i32, i32 }>
  <{ i32 128,    ; Initial async context size without space for frame
     i32 trunc ( ; Relative pointer to async function
       i64 sub (
         i64 ptrtoint (void (i8*, %async.task*, %async.actor*)* @my_async_function to i64),
         i64 ptrtoint (i32* getelementptr inbounds (<{ i32, i32 }>, <{ i32, i32 }>* @my_async_function_fp, i32 0, i32 1) to i64)
       )
     to i32)
  }>

define void @my_async_function.my_other_async_function_fp.apply(i8* %async.ctxt, %async.task %task, %async.actor* %actor, %async.actor* %target.actor) {
  ; if (%actor  != %target.actor) {
  ;   %task->resumeFromSuspension = my_other_async_function_fp.2 ;
  ;   %task->suspendedContext=%async.ctxt;
  ;   tail call swift_asyncSuspend(%actor, %target.actor, %task)
  ; } else {
  ;   tail call @my_other_async_function_fp.2(%async.ctxt, %actor, task%)
  ; }
  ret void
}

define void @my_async_function(i8* %async.ctxt, %async.task* %task, %async.actor* %actor) {
entry:
  %id = call token @llvm.coro.id.async(i32 16, i32 128, i8* %async.ctxt, i8* bitcast (<{i32, i32}>* @my_async_function_fp to i8*))
  %hdl = call i8* @llvm.coro.begin(token %id, i8* null)

	; Begin lowering: apply %my_other_async_function(%args...)
  ; setup callee context
  %callee_context = call i8* @llvm.coro.async.alloc_call(%async.task* %task, <{ i32, i32}>* @my_other_async_function_fp)
	%callee_context.0 = bitcast i8* %callee_context to %async.ctxt*
  ; store arguments ...
  ; ...

  %callee_context.caller_context.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 0
  %callee_context.return_to_caller.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 1
  ; store return to caller partial function
  %storeResume.token = call token @llvm.coro.async.store_resume(void(i8*, %async.task*, %async.actor*)** %callee_context.return_to_caller.addr)
  ; store caller context into callee context
  %store.callerContext.token = call token @llvm.core.async.store_caller_ctxt(i8** %callee_context.caller_context.addr)
  call void (...) @llvm.coro.suspend.async.void(token %storeResume.token,
                                                token %store.callerContext.token,
                                                i8* %callee_context,
                                                void (i8*, %async.task, %async.actor*, %async.actor*)* @my_async_function.my_other_async_function_fp.apply,
                                                i8* %callee_context, %async.task* %task, %async.actor *%actor, %async.actor* %actor)
  br label %resume

resume:
  ; resume.partial.function:
  ; implicit %callee_context_2 = %arg0 of @resume.my_async_function(i8*, ...)
  ; implicit %async.ctxt = load (gep 0, 0, %callee_context_2)
  ; %callee_context = %callee_context_2
  ; load results
  ; deallocate callee context
  call void @llvm.coro.async.dealloc_call(i8* %callee_context)


  ; probably need something to make sure that this is the last call.
  tail call void @swift_asyncReturn(i8* %async.ctxt, %async.task* %task, %async.actor* %actor)
  call i1 @llvm.coro.end(i8* %hdl, i1 0)
  unreachable
}

; Example of get_async_continuation/await_async_continuation

define void @my_cc_continuation(i8* %async.ctx, %async.task* %task, %async.actor %actor) {
  ret void
}

@my_with_cc_function_fp = constant <{ i32, i32 }>
  <{ i32 128,    ; Initial async context size without space for frame
     i32 trunc ( ; Relative pointer to async function
       i64 sub (
         i64 ptrtoint (void (i8*, %async.task*, %async.actor*)* @my_with_cc_function to i64),
         i64 ptrtoint (i32* getelementptr inbounds (<{ i32, i32 }>, <{ i32, i32 }>* @my_with_cc_function_fp, i32 0, i32 1) to i64)
       )
     to i32)
  }>

declare void @resume_cc_eventually(i8* %async.ctxt)

declare void @signal_await_finished(i8* %async.ctxt)

declare void @await_async_continuation(i8* %async.ctxt)

@resume_cc_eventually_fp = constant <{ i32, i32 }>
  <{ i32 136,    ; Initial async context size without space for frame + ptrsize for resumption function
     i32 0       ; This pointer is never called
  }>

define void @await_resumption_function(i8* %async.ctxt, %async.task* %task, %async.actor* %actor) {
  call void @await_async_continuation(i8* %async.ctxt)

	%callee_context.0 = bitcast i8* %async.ctxt to %async.ctxt*
  ; this is really  a projection into the tail of the context
  %resumption_return_to_caller.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 1
  %continuation = load void(i8*, %async.task* , %async.actor*)*, void(i8*, %async.task* , %async.actor*)** %resumption_return_to_caller.addr
  tail call void %continuation(i8* %async.ctxt, %async.task* %task, %async.actor* %actor)
  ret void
}

define void @my_with_cc_function(i8* %async.ctxt, %async.task* %task, %async.actor* %actor) {
entry:
  %id = call token @llvm.coro.id.async(i32 16, i32 128, i8* %async.ctxt, i8* bitcast (<{i32, i32}>* @my_with_cc_function_fp to i8*))
  %hdl = call i8* @llvm.coro.begin(token %id, i8* null)

  ; get_async_continuation lowering
  %callee_context = call i8* @llvm.coro.async.alloc_call(%async.task* %task, <{ i32, i32}>* @my_other_async_function_fp)
	%callee_context.0 = bitcast i8* %callee_context to %async.ctxt*
  ; Store the return to caller field
  %return_to_caller.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 1
  store void(i8*, %async.task* , %async.actor*)* @await_resumption_function, void(i8*, %async.task* , %async.actor*)** %return_to_caller.addr

  ; Store eventual (after await handshake) return to caller partial function.
  ; This is really a projection into the tail of the context and not as spelled '(gep 0, 1)' this should be something like '(gep 0, #last_field)'
  %resumption_return_to_caller.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 1
  %storeResume.token = call token @llvm.coro.async.store_resume(void(i8*, %async.task*, %async.actor*)** %resumption_return_to_caller.addr)
  ; Store caller context into callee context.
  %callee_context.caller_context.addr = getelementptr inbounds %async.ctxt, %async.ctxt* %callee_context.0, i32 0, i32 0
  %store.callerContext.token = call token @llvm.core.async.store_caller_ctxt(i8** %callee_context.caller_context.addr)

  ; use the current continuation
  call void @resume_cc_eventually(i8* %callee_context)

  ; await_async_continuation lowering
  call void (...) @llvm.coro.suspend.async.void(token %storeResume.token,
                                                token %store.callerContext.token,
                                                i8* %callee_context,
                                                void (i8*)* @signal_await_finished,
                                                i8* %callee_context)
  br label %resume

resume:
  ; resume.partial.function:
  ; implicit %callee_context_2 = %arg0 of @resume.my_with_cc_function(i8*, ...)
  ; implicit %async.ctxt = load (gep 0, 0, %callee_context_2)
  ; %callee_context = %callee_context_2
  ; load results
  ; deallocate callee context
  call void @llvm.coro.async.dealloc_call(i8* %callee_context)


  ; probably need something to make sure that this is the last call.
  tail call void @swift_asyncReturn(i8* %async.ctxt, %async.task* %task, %async.actor* %actor)
  call i1 @llvm.coro.end(i8* %hdl, i1 0)
  unreachable
}

declare token @llvm.coro.id.async(i32, i32, i8*, i8*)
declare i8* @llvm.coro.begin(token, i8*)
declare i1 @llvm.coro.end(i8*, i1)
declare void @llvm.coro.suspend.async.void(...)
declare i8* @llvm.coro.async.alloc_call(%async.task*, <{i32, i32}>*)
declare void @llvm.coro.async.dealloc_call(i8*)
declare void @swift_asyncReturn(i8*, %async.task*, %async.actor*)
declare token @llvm.coro.async.store_resume(void(i8*, %async.task*, %async.actor*)**)
declare token @llvm.core.async.store_caller_ctxt(i8**)

