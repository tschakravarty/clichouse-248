set allow_experimental_json_type=1;

select '{}'::json(500); -- {clientError SYNTAX_ERROR}
