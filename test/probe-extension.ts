// An omp extension that registers one tool that does nothing, for the tests.
export default function probe(pi: any) {
  pi.registerTool({
    name: "extension_probe",
    label: "Probe",
    description: "A test tool that does nothing.",
    parameters: { type: "object", properties: {} },
    async execute() {
      return { content: [{ type: "text", text: "probe" }], details: {} };
    },
  });
}
