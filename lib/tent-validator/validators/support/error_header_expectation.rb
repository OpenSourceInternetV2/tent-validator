ApiValidator::Header.register(:error, {
  'Content-Type' => %r{\Aapplication/vnd\.tent\.error\.v0\+json\b}
})
