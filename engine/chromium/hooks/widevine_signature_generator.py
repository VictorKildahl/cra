# Cra engine test build: Google's Widevine signer isn't in public checkouts. Writes an empty signature so an
# official build with enable_widevine links; Cra plays DRM through WebKit (FairPlay), not Widevine.
import argparse
p = argparse.ArgumentParser()
p.add_argument("--input_file")
p.add_argument("--output_file")
p.add_argument("--flags")
p.add_argument("--ignore_missing_cert", action="store_true")
a = p.parse_args()
open(a.output_file, "wb").close()
