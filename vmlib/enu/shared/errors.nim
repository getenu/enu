type ErrorData* = tuple[id: int, msg: string]

# :( there must be a way to do this with a table or an array
proc to_exception*(self: ErrorData): ref Exception =
  case self.id
  of 0:
    nil
  of 1:
    (ref NilAccessDefect)(msg: self.msg)
  of 2:
    (ref DivByZeroDefect)(msg: self.msg)
  of 3:
    (ref AssertionDefect)(msg: self.msg)
  of 4:
    (ref KeyError)(msg: self.msg)
  else:
    raise_assert "Unknown error id " & $self.id

proc from_exception*(self: ref Exception): ErrorData =
  if self == nil:
    (0, "")
  elif self of ref NilAccessDefect:
    (1, self.msg)
  elif self of ref DivByZeroDefect:
    (2, self.msg)
  elif self of ref AssertionDefect:
    (3, self.msg)
  elif self of ref KeyError:
    (4, self.msg)
  else:
    raise_assert "Unknown error type"
