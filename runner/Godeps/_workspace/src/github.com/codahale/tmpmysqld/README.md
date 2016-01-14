tmpmysqld
=========

`tmpmysqld` allows you to spin up temporary instances of `mysqld` for testing
purposes:

```go
func TestMySQLServer(t *testing.T) {
	server, err := NewMySQLServer("test")
	if err != nil {
		t.Fatal(err)
	}
	defer server.Stop()

	if _, err := server.DB.Exec(`
CREATE TABLE things (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL
)
`); err != nil {
		t.Error(err)
    }

    // use temporary mysqld instance
    ...
}

```

For documentation, check [godoc](http://godoc.org/github.com/codahale/tmpmysqld).
