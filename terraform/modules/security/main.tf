locals {
  # Flatten so a rule with multiple cidr_blocks produces one ingress resource per CIDR.
  # Keys are built only from statically-known config (index + literal CIDR strings),
  # never from values that are only known after apply.
  cidr_ingress = flatten([
    for idx, rule in var.cidr_ingress_rules : [
      for cidr in rule.cidr_blocks : {
        key         = "${idx}-${cidr}"
        description = rule.description
        from_port   = rule.from_port
        to_port     = rule.to_port
        protocol    = rule.protocol
        cidr        = cidr
      }
    ]
  ])
}

resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = {
    Name = var.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = { for rule in local.cidr_ingress : rule.key => rule }

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "sg" {
  # Keyed by list index (known statically), not by the SG id value itself.
  for_each = { for idx, rule in var.sg_ingress_rules : idx => rule }

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = each.value.source_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
