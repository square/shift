package migration

import (
	"errors"
	"fmt"
)

var (
	ErrDbConnect  = errors.New("migration: failed to connect to the database")
	ErrStateFile  = errors.New("migration: problem reading statefile")
	ErrTableStats = errors.New("migration: collecting table stats query didn't return as expected. This is likely due to either " +
		"the database name or table name being incorrect.")
	ErrDryRunCreatesNew = errors.New("migration: a dry run for creating the table/view didn't run as expected. This is likely due " +
		"to the table/view already existing.")
	ErrDirectDrop            = errors.New("migration: could not figure out how to drop the table/view directly.")
	ErrPtOscStdout           = errors.New("migration: failed to get stdout of pt-online-schema-change")
	ErrPtOscStderr           = errors.New("migration: failed to get stderr of pt-online-schema-change")
	ErrPtOscUnexpectedStderr = errors.New("migration: pt-online-schema-change stderr not as expected")
)

type ErrQueryFailed struct {
	Query string
	Err   error
}

func NewErrQueryFailed(query string, err error) ErrQueryFailed {
	return ErrQueryFailed{
		Query: query,
		Err:   err,
	}
}

func (e ErrQueryFailed) Error() string {
	return fmt.Sprintf("migration: the query '%s' failed: %s", e.Query, e.Err)
}

type ErrInvalidInsert struct {
	Err error
}

func NewErrInvalidInsert(err error) ErrInvalidInsert {
	return ErrInvalidInsert{
		Err: err,
	}
}

func (e ErrInvalidInsert) Error() string {
	return fmt.Sprintf("migration: invalid final insert statement: %s", e.Err)
}
