#!/bin/bash
mdbook build
rm -rf docs
mv book docs