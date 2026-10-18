// Каркас диагностики. Запуск туннеля ещё не реализован.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
)

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}

func run(args []string, output io.Writer) error {
	if len(args) == 4 && args[0] == "--inspect-backend" && args[2] == "--sha256" {
		if err := upstream.VerifyBinary(args[1], args[3]); err != nil {
			return err
		}
		return json.NewEncoder(output).Encode(map[string]any{
			"compatible": true, "upstreamRevision": upstream.Revision, "canStart": false,
		})
	}
	if len(args) != 1 || args[0] != "--capabilities" {
		return fmt.Errorf("используйте --capabilities или --inspect-backend PATH --sha256 HASH; запуск туннеля недоступен")
	}
	return json.NewEncoder(output).Encode(map[string]any{
		"protocolVersion": 1, "status": "scaffold", "canStart": false,
		"backend": "bropines/awg-wireproxy", "upstreamRevision": upstream.Revision,
		"backendDistribution": "separate", "backendCliContract": 2,
	})
}
