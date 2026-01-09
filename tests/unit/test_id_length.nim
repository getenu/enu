import pkg/model_citizen

var ctx = ZenContext.init(id = "test")
var seq1 = ZenSeq[int].init(ctx = ctx)
# Skip ZenTable due to flatty conflict

echo "ZenSeq ID: ", seq1.id, " (len=", seq1.id.len, ")"
echo ""
echo "Expected old format: ZenSeq[int]-abcdefghijklm (28+ chars)"
echo "Expected new format: abcdefghijklm (13 chars)"
